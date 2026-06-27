package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import java.net.HttpURLConnection
import java.net.URL

// ── Typed fetch result (Change #6) ────────────────────────────────────────
// Previously fetchAndSample() either returned a list or threw a generic
// Exception with a plain-text message. MainActivity had no way to distinguish
// *why* the list was empty — network error? bad encoding? all unknown schemes?
//
// Now we surface a sealed class so MainActivity can emit a distinct Flutter
// error code for each failure mode, giving the user an actionable message.
sealed class FetchResult {
    /** Subscription fetched and decoded successfully. */
    data class Success(val uris: List<String>) : FetchResult()

    /** HTTP layer returned an empty body (Content-Length: 0 or blank response). */
    data object EmptyBody : FetchResult()

    /**
     * Body was non-empty but neither base64 variant nor plain-text yielded
     * any lines containing a known proxy scheme. Likely a login wall, 404
     * HTML page, or a format we don't handle yet.
     */
    data object DecodeFailure : FetchResult()

    /**
     * Decoded successfully but every line was filtered out — the subscription
     * only contains schemes we don't support (e.g. wireguard://, ss-android://).
     */
    data object NoValidSchemes : FetchResult()

    /** Network or HTTP error after all retries exhausted. */
    data class NetworkError(val message: String) : FetchResult()
}

object SubscriptionFetcher {

    private val VALID_SCHEMES = listOf(
        "vless://", "vmess://", "trojan://", "ss://",
        "tuic://", "hysteria2://", "hy2://"
    )

    // Change #2 — retry constants
    // Mobile networks are flaky: a brief handoff between cell towers during
    // a single-attempt fetch kills the whole session. Three attempts with
    // exponential backoff handle the vast majority of transient failures.
    private const val MAX_RETRIES    = 3
    private const val BACKOFF_BASE_MS = 1_000L   // 1s, 2s, 4s

    // Change #7 — single combined timeout per attempt
    // Previously connectTimeout and readTimeout were set independently, so a
    // slow server could take connectTimeout + readTimeout = 60s before failing.
    // Now ATTEMPT_TIMEOUT_MS is the total budget for one HTTP exchange.
    // We split it 40/60 between connect and read — connect is usually fast,
    // read is where slow servers linger.
    private const val ATTEMPT_TIMEOUT_MS = 20_000   // 20s per attempt
    private const val CONNECT_TIMEOUT_MS = (ATTEMPT_TIMEOUT_MS * 0.4).toInt()  // 8s
    private const val READ_TIMEOUT_MS    = (ATTEMPT_TIMEOUT_MS * 0.6).toInt()  // 12s

    /**
     * Fetches a subscription URL, decodes it, filters valid proxy URIs,
     * and returns a uniformly sampled subset wrapped in a [FetchResult].
     *
     * Sampling model (v1.2.0):
     *   testCount = desired number of URIs to test.
     *   sampleN   = totalValid / testCount  (computed internally)
     *   testCount = 0 → test everything
     *
     * @param subURL    The subscription URL to fetch
     * @param testCount How many URIs to test. 0 = test all.
     * @return [FetchResult] — caller pattern-matches to get the URI list or
     *         a typed failure reason.
     */
    fun fetchAndSample(
        subURL:    String,
        testCount: Int = 200
    ): FetchResult {

        // Change #2 — retry loop with exponential backoff
        var lastError: String = "unknown error"
        repeat(MAX_RETRIES) { attempt ->
            if (attempt > 0) {
                val backoffMs = BACKOFF_BASE_MS * (1L shl (attempt - 1)) // 1s, 2s, 4s
                Thread.sleep(backoffMs)
            }

            val body = try {
                httpGet(subURL)
            } catch (e: Exception) {
                lastError = e.message ?: "HTTP error"
                return@repeat   // try next attempt
            }

            // Change #6 — distinguish empty body from decode failure
            if (body.isBlank()) return FetchResult.EmptyBody

            val lines = decode(body) ?: return FetchResult.DecodeFailure

            val valid = lines.filter { line ->
                VALID_SCHEMES.any { line.startsWith(it) }
            }
            if (valid.isEmpty()) return FetchResult.NoValidSchemes

            val sampled = if (testCount <= 0 || testCount >= valid.size) {
                valid
            } else {
                val sampleN = maxOf(valid.size / testCount, 1)
                uniformSample(valid, sampleN)
            }
            return FetchResult.Success(sampled)
        }

        return FetchResult.NetworkError(lastError)
    }

    // ── HTTP GET ───────────────────────────────────────────────────────────
    // Change #7: uses CONNECT_TIMEOUT_MS + READ_TIMEOUT_MS instead of a flat
    // timeoutMs applied to both. Total budget = ATTEMPT_TIMEOUT_MS (20s).
    private fun httpGet(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout          = CONNECT_TIMEOUT_MS
        conn.readTimeout             = READ_TIMEOUT_MS
        conn.requestMethod           = "GET"
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "ProxySmith/1.2")
        try {
            conn.connect()
            val code = conn.responseCode
            if (code !in 200..299) throw Exception("HTTP $code")
            return conn.inputStream.bufferedReader().readText()
        } finally {
            conn.disconnect()
        }
    }

    // ── DECODE ─────────────────────────────────────────────────────────────
    // Returns null if neither base64 variant nor plain text produced any
    // non-empty lines — the caller treats null as DecodeFailure.
    private fun decode(body: String): List<String>? {
        val trimmed = body.trim()
        tryBase64(trimmed, Base64.DEFAULT)?.let  { return it }
        tryBase64(trimmed, Base64.NO_PADDING)?.let { return it }
        val plain = trimmed.lines().map { it.trim() }.filter { it.isNotEmpty() }
        return if (plain.isEmpty()) null else plain
    }

    private fun tryBase64(s: String, flags: Int): List<String>? {
        return try {
            val decoded = String(Base64.decode(s, flags))
            if (VALID_SCHEMES.none { decoded.contains(it) }) return null
            decoded.lines().map { it.trim() }.filter { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }

    // ── UNIFORM SAMPLE ─────────────────────────────────────────────────────
    private fun uniformSample(uris: List<String>, sampleN: Int): List<String> {
        val rng    = java.util.Random(System.currentTimeMillis())
        val result = mutableListOf<String>()
        var i      = 0
        while (i < uris.size) {
            val bucket = uris.subList(i, minOf(i + sampleN, uris.size))
            result.add(bucket[rng.nextInt(bucket.size)])
            i += sampleN
        }
        return result
    }
}
