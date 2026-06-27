package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import java.net.HttpURLConnection
import java.net.URL

object SubscriptionFetcher {

    private val VALID_SCHEMES = listOf(
        "vless://", "vmess://", "trojan://", "ss://",
        "tuic://", "hysteria2://", "hy2://"
    )

    /**
     * Fetches a subscription URL, decodes it, filters valid proxy URIs,
     * and returns a uniformly sampled subset.
     *
     * Sampling model (v1.2.0):
     *   The caller passes [testCount] — the desired number of URIs to test.
     *   We compute sampleN = totalValid / testCount internally.
     *   This is more intuitive than a raw "every Nth entry" sampleN param,
     *   especially for subscription lists that range from 6 000 to 10 000 configs.
     *
     *   Examples (list = 8 000 URIs):
     *     testCount = 100  → sampleN = 80  → test ~100 URIs  (~1.3%)
     *     testCount = 300  → sampleN = 26  → test ~300 URIs  (~3.8%)
     *     testCount = 0    → test everything (sampleN = 1)
     *
     * TODO (UX pass): expose testCount to the user via a slider or text field
     *   replacing the current "SAMPLE RATE" input. The backend is ready;
     *   the Flutter UI still sends sampleN for now (mapped via testCount below).
     *
     * @param subURL    The subscription URL to fetch (http or https)
     * @param testCount How many URIs to test. 0 = test all. (replaces sampleN)
     * @param timeoutMs HTTP connect + read timeout in milliseconds (default 30s)
     * @return List of proxy URI strings ready to pass into the pipeline
     */
    fun fetchAndSample(
        subURL:    String,
        testCount: Int = 200,
        timeoutMs: Int = 30_000
    ): List<String> {
        val body = try {
            httpGet(subURL, timeoutMs)
        } catch (e: Exception) {
            throw Exception("Failed to fetch subscription from $subURL: ${e.message}", e)
        }

        val lines = decode(body)
        val valid = lines.filter { line ->
            VALID_SCHEMES.any { line.startsWith(it) }
        }
        if (valid.isEmpty()) return emptyList()

        // testCount = 0 means "test everything"
        if (testCount <= 0 || testCount >= valid.size) return valid

        // Derive sampleN from the desired test count.
        // Floor division means we might get slightly more than testCount — that's fine.
        val sampleN = maxOf(valid.size / testCount, 1)
        return uniformSample(valid, sampleN)
    }

    // ── HTTP GET ───────────────────────────────────────────────────────────
    // Uses HttpURLConnection (not HttpsURLConnection) so both http:// and
    // https:// URLs work. The JVM promotes https:// to HttpsURLConnection
    // automatically under the hood.
    private fun httpGet(url: String, timeoutMs: Int): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout          = timeoutMs
        conn.readTimeout             = timeoutMs
        conn.requestMethod           = "GET"
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("User-Agent", "ProxySmith/1.0")
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
    // Subscription content arrives as either:
    //   • Standard base64 (padded)
    //   • Raw base64 (no padding)
    //   • Plain text, one URI per line
    private fun decode(body: String): List<String> {
        val trimmed = body.trim()
        tryBase64(trimmed, Base64.DEFAULT)?.let  { return it }
        tryBase64(trimmed, Base64.NO_PADDING)?.let { return it }
        return trimmed.lines().map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun tryBase64(s: String, flags: Int): List<String>? {
        return try {
            val decoded = String(Base64.decode(s, flags))
            // Sanity check: decoded text must contain at least one known scheme;
            // if none found we likely decoded a non-base64 body into garbage.
            if (VALID_SCHEMES.none { decoded.contains(it) }) return null
            decoded.lines().map { it.trim() }.filter { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }

    // ── UNIFORM SAMPLE ─────────────────────────────────────────────────────
    // Divides the list into fixed-size buckets and picks one random URI per
    // bucket. This gives even coverage across the whole subscription list,
    // unlike pure random sampling which tends to cluster in the middle.
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
