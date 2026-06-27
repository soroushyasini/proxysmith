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
     * @param subURL    The subscription URL to fetch (http or https)
     * @param sampleN   Bucket size for uniform sampling.
     *                  1 or 0 = use every URI; 5 = ~20%; 10 = ~10%
     * @param timeoutMs HTTP connect + read timeout in milliseconds (default 30s)
     * @return List of proxy URI strings ready to test
     */
    fun fetchAndSample(
        subURL:    String,
        sampleN:   Int = 5,
        timeoutMs: Int = 30_000
    ): List<String> {
        // Wrap the HTTP call so callers get a clear error instead of a raw
        // SocketException / UnknownHostException with no URL context
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

        // sampleN <= 1 means "test everything" — also guards the infinite-loop
        // that occurred when sampleN = 0 (bucket index never advanced)
        if (sampleN <= 1) return valid
        return uniformSample(valid, sampleN)
    }

    // ── HTTP GET ───────────────────────────────────────────────────────────
    // Uses the base HttpURLConnection (not HttpsURLConnection) so both
    // http:// and https:// URLs work — the JVM promotes https:// connections
    // to HttpsURLConnection automatically under the hood.
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

        tryBase64(trimmed, Base64.DEFAULT)?.let { return it }
        tryBase64(trimmed, Base64.NO_PADDING)?.let { return it }

        // Fall back to plain text
        return trimmed.lines().map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun tryBase64(s: String, flags: Int): List<String>? {
        return try {
            val decoded = String(Base64.decode(s, flags))
            // Sanity check: decoded text must contain at least one known scheme;
            // otherwise we likely decoded a non-base64 body and got garbage
            if (VALID_SCHEMES.none { decoded.contains(it) }) return null
            decoded.lines().map { it.trim() }.filter { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }

    // ── UNIFORM SAMPLE ─────────────────────────────────────────────────────
    // Divides the list into fixed-size buckets and picks one random URI per
    // bucket. This gives even coverage across the whole list, unlike pure
    // random sampling which tends to cluster around the middle.
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
