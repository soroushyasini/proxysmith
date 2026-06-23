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
     * Fetches a subscription URL, decodes it, filters valid URIs,
     * and returns a uniformly sampled subset.
     *
     * @param subURL   The subscription URL to fetch (http or https)
     * @param sampleN  1 = test all, 5 = test ~20%, 10 = test ~10%, 0 = test all
     * @param timeoutMs HTTP timeout in milliseconds (default 30s)
     * @return List of proxy URI strings
     */
    fun fetchAndSample(
        subURL: String,
        sampleN: Int = 5,
        timeoutMs: Int = 30_000
    ): List<String> {
        val body = httpGet(subURL, timeoutMs)
        val lines = decode(body)
        val valid = lines.filter { line ->
            VALID_SCHEMES.any { line.startsWith(it) }
        }
        if (valid.isEmpty()) return emptyList()
        // FIX: Guard sampleN <= 0 — previously 0 would cause an infinite loop
        // in uniformSample because the bucket index never advanced.
        if (sampleN <= 1) return valid
        return uniformSample(valid, sampleN)
    }

    // ── HTTP GET ───────────────────────────────────────────────────────────
    // FIX: Was hardcoded to HttpsURLConnection, crashing on http:// URLs with
    // a ClassCastException. Now uses the base HttpURLConnection which works
    // for both http and https (the JVM upcasts to HttpsURLConnection automatically
    // for https:// URLs under the hood).
    private fun httpGet(url: String, timeoutMs: Int): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = timeoutMs
        conn.readTimeout    = timeoutMs
        conn.requestMethod  = "GET"
        conn.setRequestProperty("User-Agent", "ProxySmith/1.0")
        conn.instanceFollowRedirects = true
        try {
            conn.connect()
            val code = conn.responseCode
            if (code !in 200..299) throw Exception("HTTP $code from $url")
            return conn.inputStream.bufferedReader().readText()
        } finally {
            conn.disconnect()
        }
    }

    // ── DECODE ─────────────────────────────────────────────────────────────
    // Tries StdEncoding, then RawStdEncoding, then plain text
    private fun decode(body: String): List<String> {
        val trimmed = body.trim()

        // Try standard base64
        tryBase64(trimmed, Base64.DEFAULT)?.let { return it }

        // Try raw (no padding)
        tryBase64(trimmed, Base64.NO_PADDING)?.let { return it }

        // Plain text (already one URI per line)
        return trimmed.lines().map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun tryBase64(s: String, flags: Int): List<String>? {
        return try {
            val decoded = String(Base64.decode(s, flags))
            // Sanity check: decoded text should contain known schemes
            if (VALID_SCHEMES.none { decoded.contains(it) }) return null
            decoded.lines().map { it.trim() }.filter { it.isNotEmpty() }
        } catch (e: Exception) {
            null
        }
    }

    // ── UNIFORM SAMPLE ─────────────────────────────────────────────────────
    // Divides list into buckets of size sampleN, picks one random per bucket.
    // Gives uniform coverage across the list (not pure random which clusters).
    private fun uniformSample(uris: List<String>, sampleN: Int): List<String> {
        val rng = java.util.Random(System.currentTimeMillis())
        val result = mutableListOf<String>()
        var i = 0
        while (i < uris.size) {
            val end = minOf(i + sampleN, uris.size)
            val bucket = uris.subList(i, end)
            result.add(bucket[rng.nextInt(bucket.size)])
            i += sampleN
        }
        return result
    }
}
