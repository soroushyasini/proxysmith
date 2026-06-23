package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import org.json.JSONObject
import org.json.JSONArray

object UriParser {

    fun parseURIToOutbound(uri: String): JSONObject {
        // Strip fragment
        val clean = uri.substringBefore("#").trim()

        return when {
            clean.startsWith("vless://") -> parseVless(clean)
            clean.startsWith("vmess://") -> parseVmess(clean)
            clean.startsWith("trojan://") -> parseTrojan(clean)
            clean.startsWith("ss://") -> parseSS(clean)
            else -> throw IllegalArgumentException("Unsupported scheme: $clean")
        }
    }

    // ── VLESS ──────────────────────────────────────────────────────────────
    private fun parseVless(uri: String): JSONObject {
        val url = java.net.URI(uri)
        val uuid = url.userInfo ?: throw IllegalArgumentException("vless: missing uuid")
        val host = url.host
        val port = url.port

        val params = parseQuery(url.rawQuery)
        val security = params["security"] ?: "none"
        val network  = params["type"] ?: "tcp"
        val flow     = params["flow"] ?: ""
        val sni      = params["sni"] ?: params["peer"] ?: host

        val vnext = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("users", JSONArray().put(JSONObject().apply {
                put("id", uuid)
                put("encryption", "none")
                if (flow.isNotEmpty()) put("flow", flow)
            }))
        }

        val settings = JSONObject().put("vnext", JSONArray().put(vnext))

        val streamSettings = buildStreamSettings(network, security, sni, params)

        return JSONObject().apply {
            put("protocol", "vless")
            put("settings", settings)
            put("streamSettings", streamSettings)
        }
    }

    // ── VMESS ──────────────────────────────────────────────────────────────
    private fun parseVmess(uri: String): JSONObject {
        val b64 = uri.removePrefix("vmess://")
        val json = decodeBase64(b64)
        val v = JSONObject(json)

        val host = v.getString("add")
        val port = when {
            v.has("port") -> v.get("port").toString().toInt()
            else -> 443
        }
        val uuid    = v.getString("id")
        val alterId = v.optInt("aid", 0)
        val network = v.optString("net", "tcp")
        val tls     = v.optString("tls", "")
        val sni     = v.optString("sni", v.optString("host", host))

        val vnext = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("users", JSONArray().put(JSONObject().apply {
                put("id", uuid)
                put("alterId", alterId)
                put("security", "auto")
            }))
        }

        val settings = JSONObject().put("vnext", JSONArray().put(vnext))

        val params = mutableMapOf<String, String>()
        if (v.has("path")) params["path"] = v.getString("path")
        if (v.has("host")) params["host"] = v.getString("host")
        if (v.has("type")) params["headerType"] = v.getString("type")

        val security = if (tls == "tls") "tls" else "none"
        val streamSettings = buildStreamSettings(network, security, sni, params)

        return JSONObject().apply {
            put("protocol", "vmess")
            put("settings", settings)
            put("streamSettings", streamSettings)
        }
    }

    // ── TROJAN ─────────────────────────────────────────────────────────────
    private fun parseTrojan(uri: String): JSONObject {
        val url = java.net.URI(uri)
        val password = url.userInfo ?: throw IllegalArgumentException("trojan: missing password")
        val host = url.host
        val port = url.port

        val params = parseQuery(url.rawQuery)
        val sni = params["sni"] ?: params["peer"] ?: host
        val network = params["type"] ?: "tcp"

        val server = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("password", password)
        }

        val settings = JSONObject().put("servers", JSONArray().put(server))
        val streamSettings = buildStreamSettings(network, "tls", sni, params)

        return JSONObject().apply {
            put("protocol", "trojan")
            put("settings", settings)
            put("streamSettings", streamSettings)
        }
    }

    // ── SHADOWSOCKS ────────────────────────────────────────────────────────
    private fun parseSS(uri: String): JSONObject {
        val withoutScheme = uri.removePrefix("ss://")

        val (userinfo, hostpart) = if (withoutScheme.contains("@")) {
            val atIdx = withoutScheme.lastIndexOf("@")
            val decoded = decodeBase64Safe(withoutScheme.substring(0, atIdx))
                ?: withoutScheme.substring(0, atIdx)
            decoded to withoutScheme.substring(atIdx + 1)
        } else {
            // entire thing before ? is base64
            val qIdx = withoutScheme.indexOf("?").let { if (it < 0) withoutScheme.length else it }
            val decoded = decodeBase64Safe(withoutScheme.substring(0, qIdx))
                ?: throw IllegalArgumentException("ss: cannot decode userinfo")
            // decoded should be "method:password@host:port"
            val atIdx = decoded.lastIndexOf("@")
            if (atIdx < 0) throw IllegalArgumentException("ss: bad decoded format")
            decoded.substring(0, atIdx) to decoded.substring(atIdx + 1)
        }

        val colonIdx = userinfo.indexOf(":")
        if (colonIdx < 0) throw IllegalArgumentException("ss: missing method:password")
        val method   = userinfo.substring(0, colonIdx)
        val password = userinfo.substring(colonIdx + 1)

        val hostPort = hostpart.substringBefore("?").substringBefore("#")
        val lastColon = hostPort.lastIndexOf(":")
        val host = hostPort.substring(0, lastColon)
        val port = hostPort.substring(lastColon + 1).toInt()

        val server = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("method", method)
            put("password", password)
        }

        val settings = JSONObject().put("servers", JSONArray().put(server))

        return JSONObject().apply {
            put("protocol", "shadowsocks")
            put("settings", settings)
            put("streamSettings", JSONObject().put("network", "tcp"))
        }
    }

    // ── STREAM SETTINGS ────────────────────────────────────────────────────
    private fun buildStreamSettings(
        network: String,
        security: String,
        sni: String,
        params: Map<String, String>
    ): JSONObject {
        val ss = JSONObject()
        ss.put("network", network)
        ss.put("security", security)

        when (security) {
            "tls" -> ss.put("tlsSettings", JSONObject().apply {
                put("serverName", sni)
                put("allowInsecure", false)
            })
            "reality" -> ss.put("realitySettings", JSONObject().apply {
                put("serverName", sni)
                put("fingerprint", params["fp"] ?: "chrome")
                put("shortId", params["sid"] ?: "")
                put("publicKey", params["pbk"] ?: "")
                put("spiderX", params["spx"] ?: "")
            })
        }

        when (network) {
            "ws" -> ss.put("wsSettings", JSONObject().apply {
                put("path", params["path"] ?: "/")
                put("headers", JSONObject().put("Host", params["host"] ?: sni))
            })
            "grpc" -> ss.put("grpcSettings", JSONObject().apply {
                put("serviceName", params["serviceName"] ?: params["path"] ?: "")
            })
            "http", "h2" -> ss.put("httpSettings", JSONObject().apply {
                put("path", params["path"] ?: "/")
                put("host", JSONArray().put(params["host"] ?: sni))
            })
        }

        return ss
    }

    // ── HELPERS ────────────────────────────────────────────────────────────
    private fun parseQuery(query: String?): Map<String, String> {
        if (query.isNullOrEmpty()) return emptyMap()
        return query.split("&").mapNotNull {
            val eq = it.indexOf("=")
            if (eq < 0) null
            else java.net.URLDecoder.decode(it.substring(0, eq), "UTF-8") to
                 java.net.URLDecoder.decode(it.substring(eq + 1), "UTF-8")
        }.toMap()
    }

    private fun decodeBase64(s: String): String {
        val padded = s.replace("-", "+").replace("_", "/")
            .let { it + "=".repeat((4 - it.length % 4) % 4) }
        return String(Base64.decode(padded, Base64.DEFAULT))
    }

    private fun decodeBase64Safe(s: String): String? {
        return try { decodeBase64(s) } catch (e: Exception) { null }
    }
}
