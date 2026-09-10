package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import java.net.URI
import java.net.URLDecoder
import org.json.JSONArray
import org.json.JSONObject

/** Converts supported share links to the configuration shape accepted by the pinned Xray core. */
object UriParser {
    fun parseURIToOutbound(uri: String): JSONObject {
        val clean = uri.substringBefore("#").trim()
        return when {
            clean.startsWith("vless://", true) -> parseVless(clean)
            clean.startsWith("vmess://", true) -> parseVmess(clean)
            clean.startsWith("trojan://", true) -> parseTrojan(clean)
            clean.startsWith("ss://", true) -> parseShadowsocks(clean)
            clean.startsWith("hysteria2://", true) || clean.startsWith("hy2://", true) -> parseHysteria2(clean)
            else -> throw IllegalArgumentException("Unsupported proxy scheme")
        }
    }

    private fun parseVless(raw: String): JSONObject {
        val uri = URI(raw)
        val userId = uri.userInfo?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("vless: missing user ID")
        val (host, port) = endpoint(uri, "vless")
        val params = query(uri.rawQuery)
        val user = JSONObject().put("id", userId).put("encryption", "none")
        params["flow"]?.takeIf(String::isNotBlank)?.let { user.put("flow", it) }
        return outboundWithVNext("vless", host, port, user)
            .put("streamSettings", streamSettings(params["type"], params["security"], host, params))
    }

    private fun parseVmess(raw: String): JSONObject {
        val value = JSONObject(decodeBase64(raw.substringAfter("://")))
        val host = value.optString("add").takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("vmess: missing address")
        val port = value.opt("port")?.toString()?.toIntOrNull()?.takeIf { it in 1..65535 }
            ?: throw IllegalArgumentException("vmess: invalid port")
        val userId = value.optString("id").takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("vmess: missing user ID")
        val user = JSONObject().put("id", userId).put("alterId", value.optInt("aid", 0)).put("security", "auto")
        val params = mutableMapOf<String, String>()
        for (key in listOf("path", "host", "sni", "serviceName", "authority", "fp", "pbk", "sid", "spx")) {
            value.optString(key).takeIf(String::isNotBlank)?.let { params[key] = it }
        }
        val network = value.optString("net", "tcp")
        val security = if (value.optString("tls") == "tls") "tls" else "none"
        return outboundWithVNext("vmess", host, port, user)
            .put("streamSettings", streamSettings(network, security, host, params))
    }

    private fun parseTrojan(raw: String): JSONObject {
        val uri = URI(raw)
        val password = uri.userInfo?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("trojan: missing password")
        val (host, port) = endpoint(uri, "trojan")
        val params = query(uri.rawQuery)
        val server = JSONObject().put("address", host).put("port", port).put("password", password)
        return JSONObject()
            .put("protocol", "trojan")
            .put("settings", JSONObject().put("servers", JSONArray().put(server)))
            .put("streamSettings", streamSettings(params["type"], params["security"] ?: "tls", host, params))
            .put("tag", "proxy")
    }

    private fun parseShadowsocks(raw: String): JSONObject {
        val payload = raw.substringAfter("://")
        val credentials: String
        val address: String
        if (payload.contains("@")) {
            val splitAt = payload.lastIndexOf("@")
            val encodedCredentials = payload.substring(0, splitAt)
            credentials = decodeBase64Safe(encodedCredentials) ?: URLDecoder.decode(encodedCredentials, "UTF-8")
            address = payload.substring(splitAt + 1).substringBefore("?")
        } else {
            val decoded = decodeBase64(payload.substringBefore("?"))
            val splitAt = decoded.lastIndexOf("@")
            if (splitAt < 1) throw IllegalArgumentException("ss: decoded value is missing server")
            credentials = decoded.substring(0, splitAt)
            address = decoded.substring(splitAt + 1)
        }
        val separator = credentials.indexOf(":")
        if (separator < 1 || separator == credentials.lastIndex) {
            throw IllegalArgumentException("ss: invalid method or password")
        }
        val (host, port) = splitHostPort(address, "ss")
        val server = JSONObject()
            .put("address", host)
            .put("port", port)
            .put("method", credentials.substring(0, separator))
            .put("password", credentials.substring(separator + 1))
        return JSONObject()
            .put("protocol", "shadowsocks")
            .put("settings", JSONObject().put("servers", JSONArray().put(server)))
            .put("streamSettings", JSONObject().put("network", "tcp"))
            .put("tag", "proxy")
    }

    private fun parseHysteria2(raw: String): JSONObject {
        val uri = URI(raw.replaceFirst("hy2://", "hysteria2://", true))
        val secret = uri.userInfo?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("hysteria2: missing authentication secret")
        val (host, port) = endpoint(uri, "hysteria2")
        val params = query(uri.rawQuery)
        val tls = JSONObject().put("serverName", params["sni"] ?: host)
        if (booleanParam(params["insecure"])) tls.put("allowInsecure", true)
        return JSONObject()
            .put("protocol", "hysteria")
            .put("settings", JSONObject().put("version", 2).put("address", host).put("port", port))
            .put("streamSettings", JSONObject()
                .put("network", "hysteria")
                .put("security", "tls")
                .put("tlsSettings", tls)
                .put("hysteriaSettings", JSONObject().put("version", 2).put("auth", secret)))
            .put("tag", "proxy")
    }

    private fun streamSettings(
        rawNetwork: String?,
        rawSecurity: String?,
        host: String,
        params: Map<String, String>
    ): JSONObject {
        val network = when (rawNetwork?.lowercase().orEmpty().ifEmpty { "tcp" }) {
            "raw", "tcp" -> "tcp"
            "ws" -> "ws"
            "grpc" -> "grpc"
            "xhttp", "splithttp" -> "splithttp"
            "httpupgrade" -> "httpupgrade"
            else -> throw IllegalArgumentException("unsupported transport: $rawNetwork")
        }
        val security = rawSecurity?.lowercase().orEmpty().ifEmpty { "none" }
        if (security !in setOf("none", "tls", "reality")) {
            throw IllegalArgumentException("unsupported security: $security")
        }
        val sni = params["sni"] ?: params["peer"] ?: host
        val result = JSONObject().put("network", network).put("security", security)
        when (security) {
            "tls" -> result.put("tlsSettings", JSONObject().put("serverName", sni).apply {
                params["fp"]?.takeIf(String::isNotBlank)?.let { put("fingerprint", it) }
                if (booleanParam(params["allowInsecure"]) || booleanParam(params["insecure"])) put("allowInsecure", true)
            })
            "reality" -> {
                val publicKey = params["pbk"]?.takeIf(String::isNotBlank)
                    ?: throw IllegalArgumentException("Reality public key is missing")
                result.put("realitySettings", JSONObject()
                    .put("serverName", sni)
                    .put("fingerprint", params["fp"] ?: "chrome")
                    .put("publicKey", publicKey)
                    .put("shortId", params["sid"] ?: "")
                    .put("spiderX", params["spx"] ?: ""))
            }
        }
        when (network) {
            "tcp" -> result.put("tcpSettings", JSONObject().put("header", JSONObject().put("type", "none")))
            "ws" -> result.put("wsSettings", JSONObject()
                .put("path", params["path"] ?: "/")
                .put("headers", JSONObject().apply { params["host"]?.let { put("Host", it) } }))
            "grpc" -> result.put("grpcSettings", JSONObject()
                .put("serviceName", params["serviceName"] ?: params["path"] ?: "").apply {
                    params["authority"]?.let { put("authority", it) }
                })
            "splithttp" -> result.put("splithttpSettings", JSONObject().put("path", params["path"] ?: "/").apply {
                params["host"]?.let { put("host", it) }
            })
            "httpupgrade" -> result.put("httpupgradeSettings", JSONObject()
                .put("path", params["path"] ?: "/")
                .put("host", params["host"] ?: sni))
        }
        return result
    }

    private fun outboundWithVNext(protocol: String, host: String, port: Int, user: JSONObject) = JSONObject()
        .put("protocol", protocol)
        .put("settings", JSONObject().put("vnext", JSONArray().put(
            JSONObject().put("address", host).put("port", port).put("users", JSONArray().put(user))
        )))
        .put("tag", "proxy")

    private fun endpoint(uri: URI, scheme: String): Pair<String, Int> {
        val host = uri.host ?: throw IllegalArgumentException("$scheme: missing host")
        val port = uri.port.takeIf { it in 1..65535 }
            ?: throw IllegalArgumentException("$scheme: missing or invalid port")
        return host to port
    }

    private fun splitHostPort(value: String, scheme: String): Pair<String, Int> {
        val parsed = URI("$scheme://$value")
        return endpoint(parsed, scheme)
    }

    private fun query(value: String?): Map<String, String> = value.orEmpty().split("&")
        .mapNotNull { pair ->
            val separator = pair.indexOf("=")
            if (separator < 0) null else URLDecoder.decode(pair.substring(0, separator), "UTF-8") to
                URLDecoder.decode(pair.substring(separator + 1), "UTF-8")
        }.toMap()

    private fun decodeBase64(value: String): String {
        val normalized = value.replace('-', '+').replace('_', '/')
            .let { it + "=".repeat((4 - it.length % 4) % 4) }
        return String(Base64.decode(normalized, Base64.DEFAULT), Charsets.UTF_8)
    }

    private fun decodeBase64Safe(value: String): String? = runCatching { decodeBase64(value) }.getOrNull()

    private fun booleanParam(value: String?): Boolean = value?.lowercase() in setOf("1", "true", "yes")
}
