package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import kotlin.random.Random

sealed class FetchResult {
    data class Success(val uris: List<String>) : FetchResult()
    data object EmptyBody : FetchResult()
    data object DecodeFailure : FetchResult()
    data object NoValidSchemes : FetchResult()
    data class NetworkError(val message: String) : FetchResult()
}

object SubscriptionFetcher {
    private val validSchemes = setOf("vless", "vmess", "trojan", "ss", "hysteria2", "hy2")
    private const val maxRetries = 3
    private const val backoffBaseMs = 1_000L
    private const val connectTimeoutMs = 8_000
    private const val readTimeoutMs = 12_000
    private const val maxBodyBytes = 10 * 1024 * 1024
    private const val maxLineBytes = 64 * 1024

    fun fetchAndSample(subURL: String, testCount: Int = 200): FetchResult {
        if (!isValidHttpUrl(subURL)) {
            return FetchResult.NetworkError("Subscription URL must use HTTP or HTTPS")
        }
        var lastError = "unknown error"
        repeat(maxRetries) { attempt ->
            if (attempt > 0) Thread.sleep(backoffBaseMs * (1L shl (attempt - 1)))
            val body = try {
                httpGet(subURL)
            } catch (exception: Exception) {
                lastError = exception.javaClass.simpleName.ifEmpty { "HTTP error" }
                return@repeat
            }
            if (body.isBlank()) return FetchResult.EmptyBody
            val lines = decode(body) ?: return FetchResult.DecodeFailure
            val selected = selectSupportedUris(lines, testCount)
            if (selected.isEmpty()) return FetchResult.NoValidSchemes
            return FetchResult.Success(selected)
        }
        return FetchResult.NetworkError(lastError)
    }

    internal fun selectSupportedUris(
        lines: List<String>,
        testCount: Int,
        random: Random = Random.Default
    ): List<String> {
        val unique = LinkedHashMap<String, String>()
        for (raw in lines) {
            val uri = raw.trim()
            if (uri.toByteArray(Charsets.UTF_8).size > maxLineBytes) continue
            val scheme = runCatching { URI(uri).scheme?.lowercase() }.getOrNull()
            if (scheme !in validSchemes) continue
            unique.putIfAbsent(uri.substringBefore("#"), uri)
        }
        val values = unique.values.toList()
        if (testCount <= 0 || testCount >= values.size) return values
        return values.shuffled(random).take(testCount)
    }

    private fun httpGet(rawUrl: String): String {
        val connection = URL(rawUrl).openConnection() as HttpURLConnection
        connection.connectTimeout = connectTimeoutMs
        connection.readTimeout = readTimeoutMs
        connection.requestMethod = "GET"
        connection.instanceFollowRedirects = true
        connection.setRequestProperty("User-Agent", "ProxySmith/2.4")
        try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("HTTP ${connection.responseCode}")
            }
            val output = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > maxBodyBytes) throw IllegalStateException("Subscription exceeds 10 MiB limit")
                    output.write(buffer, 0, read)
                }
            }
            return output.toString(Charsets.UTF_8.name())
        } finally {
            connection.disconnect()
        }
    }

    private fun decode(body: String): List<String>? {
        val trimmed = body.trim()
        for (flags in listOf(Base64.DEFAULT, Base64.NO_PADDING, Base64.URL_SAFE, Base64.URL_SAFE or Base64.NO_PADDING)) {
            tryBase64(trimmed, flags)?.let { return it }
        }
        val plain = trimmed.lineSequence().map(String::trim).filter(String::isNotEmpty).toList()
        return plain.ifEmpty { null }
    }

    private fun tryBase64(value: String, flags: Int): List<String>? = try {
        val decoded = String(Base64.decode(value, flags), Charsets.UTF_8)
        if (!decoded.contains("://")) null
        else decoded.lineSequence().map(String::trim).filter(String::isNotEmpty).toList()
    } catch (_: Exception) {
        null
    }

    private fun isValidHttpUrl(value: String): Boolean = try {
        val uri = URI(value)
        uri.host != null && uri.scheme?.lowercase() in setOf("http", "https")
    } catch (_: Exception) {
        false
    }
}
