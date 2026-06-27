package ir.proxysmith.proxysmith_flutter

import android.util.Base64
import org.json.JSONObject
import org.json.JSONArray

/**
 * Parses proxy URIs into libv2ray-compatible outbound JSONObjects.
 *
 * Supported protocols:
 *   - VLESS   (vless://)
 *   - VMess   (vmess://)
 *   - Trojan  (trojan://)
 *   - Shadowsocks (ss://)
 *   - TUIC    (tuic://)       ← new in v1.1.0
 *   - Hysteria2 (hysteria2://, hy2://)  ← new in v1.1.0
 */
object UriParser {

    fun parseURIToOutbound(uri: String): JSONObject {
        // Strip fragment (#...) — subscription lists often append display names here
        val clean = uri.substringBefore("#").trim()

        return when {
            clean.startsWith("vless://")     -> parseVless(clean)
            clean.startsWith("vmess://")     -> parseVmess(clean)
            clean.startsWith("trojan://")    -> parseTrojan(clean)
            clean.startsWith("ss://")        -> parseSS(clean)
            clean.startsWith("tuic://")      -> parseTuic(clean)
            clean.startsWith("hysteria2://") -> parseHysteria2(clean)
            clean.startsWith("hy2://")       -> parseHysteria2(clean)   // hy2 is an alias
            else -> throw IllegalArgumentException("Unsupported scheme: $clean")
        }
    }

    // ── VLESS ──────────────────────────────────────────────────────────────
    private fun parseVless(uri: String): JSONObject {
        val url  = java.net.URI(uri)
        val uuid = url.userInfo ?: throw IllegalArgumentException("vless: missing uuid")
        val host = url.host     ?: throw IllegalArgumentException("vless: missing host")
        val port = requirePort(url.port, "vless")

        val params   = parseQuery(url.rawQuery)
        val security = params["security"] ?: "none"
        val network  = params["type"]     ?: "tcp"
        val flow     = params["flow"]     ?: ""
        // SNI: explicit sni param wins, then peer (legacy alias), then the host itself
        val sni      = params["sni"] ?: params["peer"] ?: host

        val user = JSONObject().apply {
            put("id", uuid)
            put("encryption", "none")
            // Only include flow when it's actually set — empty string causes parse errors
            if (flow.isNotEmpty()) put("flow", flow)
        }

        val vnext = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("users", JSONArray().put(user))
        }

        return JSONObject().apply {
            put("protocol", "vless")
            put("settings", JSONObject().put("vnext", JSONArray().put(vnext)))
            put("streamSettings", buildStreamSettings(network, security, sni, params))
        }
    }

    // ── VMESS ──────────────────────────────────────────────────────────────
    private fun parseVmess(uri: String): JSONObject {
        val b64  = uri.removePrefix("vmess://")
        val json = decodeBase64(b64)
        val v    = JSONObject(json)

        val host    = v.getString("add")
        // Port can be a string or an int in the wild — normalise both
        val port    = v.get("port").toString().toIntOrNull()
            ?: throw IllegalArgumentException("vmess: invalid port '${v.get("port")}'")
        val uuid    = v.getString("id")
        val alterId = v.optInt("aid", 0)
        val network = v.optString("net", "tcp")
        val tls     = v.optString("tls", "")
        // SNI: explicit sni field → host field (WS host header doubles as SNI) → server address
        val sni     = v.optString("sni", v.optString("host", host))

        val user = JSONObject().apply {
            put("id", uuid)
            put("alterId", alterId)
            put("security", "auto")
        }

        val vnext = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("users", JSONArray().put(user))
        }

        // Build the extra params map that buildStreamSettings needs
        val params = mutableMapOf<String, String>()
        if (v.has("path")) params["path"]       = v.getString("path")
        if (v.has("host")) params["host"]       = v.getString("host")
        // "type" in VMess JSON is the HTTP obfuscation header type (http/none),
        // NOT the network type. Store it separately so buildStreamSettings can
        // apply it to tcpSettings.header rather than as the network selector.
        if (v.has("type")) params["headerType"] = v.getString("type")

        val security = if (tls == "tls") "tls" else "none"

        return JSONObject().apply {
            put("protocol", "vmess")
            put("settings", JSONObject().put("vnext", JSONArray().put(vnext)))
            put("streamSettings", buildStreamSettings(network, security, sni, params))
        }
    }

    // ── TROJAN ─────────────────────────────────────────────────────────────
    private fun parseTrojan(uri: String): JSONObject {
        val url      = java.net.URI(uri)
        val password = url.userInfo ?: throw IllegalArgumentException("trojan: missing password")
        val host     = url.host     ?: throw IllegalArgumentException("trojan: missing host")
        val port     = requirePort(url.port, "trojan")

        val params  = parseQuery(url.rawQuery)
        val sni     = params["sni"] ?: params["peer"] ?: host
        val network = params["type"] ?: "tcp"

        val server = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("password", password)
        }

        return JSONObject().apply {
            put("protocol", "trojan")
            put("settings", JSONObject().put("servers", JSONArray().put(server)))
            // Trojan always runs over TLS
            put("streamSettings", buildStreamSettings(network, "tls", sni, params))
        }
    }

    // ── SHADOWSOCKS ────────────────────────────────────────────────────────
    private fun parseSS(uri: String): JSONObject {
        val withoutScheme = uri.removePrefix("ss://")

        // Two common SS URI formats:
        //   A) method:password@host:port   (userinfo may be base64-encoded)
        //   B) base64(method:password@host:port)
        val (userinfo, hostpart) = if (withoutScheme.contains("@")) {
            // Format A: split on the LAST @ to correctly handle passwords that contain @
            val atIdx   = withoutScheme.lastIndexOf("@")
            val rawUser = withoutScheme.substring(0, atIdx)
            // The userinfo portion might still be base64-encoded
            val decoded = decodeBase64Safe(rawUser) ?: rawUser
            decoded to withoutScheme.substring(atIdx + 1)
        } else {
            // Format B: the entire thing (before ?) is base64-encoded
            val qIdx    = withoutScheme.indexOf("?").takeIf { it >= 0 } ?: withoutScheme.length
            val decoded = decodeBase64Safe(withoutScheme.substring(0, qIdx))
                ?: throw IllegalArgumentException("ss: cannot decode userinfo")
            // Decoded string should be "method:password@host:port"
            val atIdx   = decoded.lastIndexOf("@")
            if (atIdx < 0) throw IllegalArgumentException("ss: decoded userinfo missing '@'")
            decoded.substring(0, atIdx) to decoded.substring(atIdx + 1)
        }

        // Split "method:password" — the first colon is the separator
        val colonIdx = userinfo.indexOf(":")
        if (colonIdx < 0) throw IllegalArgumentException("ss: missing method:password separator")
        val method   = userinfo.substring(0, colonIdx)
        val password = userinfo.substring(colonIdx + 1)

        // Strip query string and fragment from the host:port portion
        val hostPort   = hostpart.substringBefore("?").substringBefore("#")
        val (host, port) = splitHostPort(hostPort, "ss")

        val server = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("method", method)
            put("password", password)
        }

        return JSONObject().apply {
            put("protocol", "shadowsocks")
            put("settings", JSONObject().put("servers", JSONArray().put(server)))
            put("streamSettings", JSONObject().put("network", "tcp"))
        }
    }

    // ── TUIC ───────────────────────────────────────────────────────────────
    // Format: tuic://uuid:password@host:port?params
    //
    // Key params:
    //   congestion_control  bbr / cubic / new_reno
    //   alpn                comma-separated ALPN list (e.g. "h3,spdy/1")
    //   sni                 TLS server name
    //   udp_relay_mode      native / quic
    //   allow_insecure      0 / 1
    private fun parseTuic(uri: String): JSONObject {
        val url      = java.net.URI(uri)
        val userInfo = url.userInfo ?: throw IllegalArgumentException("tuic: missing uuid:password")
        val host     = url.host     ?: throw IllegalArgumentException("tuic: missing host")
        val port     = requirePort(url.port, "tuic")

        // userInfo = "uuid:password" — UUID contains hyphens but never colons, safe split
        val colonIdx = userInfo.indexOf(":")
        if (colonIdx < 0) throw IllegalArgumentException("tuic: userinfo must be uuid:password")
        val uuid     = userInfo.substring(0, colonIdx)
        val password = userInfo.substring(colonIdx + 1)

        val params             = parseQuery(url.rawQuery)
        val sni                = params["sni"] ?: host
        val congestionControl  = params["congestion_control"] ?: "bbr"
        val udpRelayMode       = params["udp_relay_mode"]     ?: "native"
        val allowInsecure      = parseBoolParam(params["allow_insecure"])

        // alpn is a comma-separated string → JSONArray
        val alpnArray = JSONArray().apply {
            val raw = params["alpn"] ?: "h3"
            raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.forEach { put(it) }
        }

        // TUIC uses its own top-level settings block (not vnext/servers)
        val tuicSettings = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("uuid", uuid)
            put("password", password)
            put("congestionControl", congestionControl)
            put("udpRelayMode", udpRelayMode)
        }

        val streamSettings = JSONObject().apply {
            put("network", "quic")       // TUIC always runs over QUIC
            put("security", "tls")
            put("tlsSettings", JSONObject().apply {
                put("serverName", sni)
                put("allowInsecure", allowInsecure)
                put("alpn", alpnArray)
            })
        }

        return JSONObject().apply {
            put("protocol", "tuic")
            put("settings", JSONObject().put("servers", JSONArray().put(tuicSettings)))
            put("streamSettings", streamSettings)
        }
    }

    // ── HYSTERIA2 / HY2 ────────────────────────────────────────────────────
    // Format: hysteria2://password@host:port?params
    //         hy2://password@host:port?params   (identical, just a shorter alias)
    //
    // Key params:
    //   sni       TLS server name
    //   insecure  0 / 1
    //   obfs      obfuscation type (currently only "salamander")
    //   obfs-password  obfuscation password (required when obfs is set)
    private fun parseHysteria2(uri: String): JSONObject {
        // Normalise both schemes to a common prefix for java.net.URI parsing
        val normalised = uri.replaceFirst("hy2://", "hysteria2://")
        val url        = java.net.URI(normalised)
        val password   = url.userInfo ?: throw IllegalArgumentException("hysteria2: missing password")
        val host       = url.host     ?: throw IllegalArgumentException("hysteria2: missing host")
        val port       = requirePort(url.port, "hysteria2")

        val params        = parseQuery(url.rawQuery)
        val sni           = params["sni"] ?: host
        val allowInsecure = parseBoolParam(params["insecure"])
        val obfsType      = params["obfs"]          // null when not present
        val obfsPassword  = params["obfs-password"] // key contains a hyphen — parseQuery handles it

        val hy2Settings = JSONObject().apply {
            put("address", host)
            put("port", port)
            put("password", password)
        }

        // Only attach obfs block when obfuscation is actually configured
        if (!obfsType.isNullOrEmpty()) {
            hy2Settings.put("obfs", JSONObject().apply {
                put("type", obfsType)
                // obfs-password is required when obfs is set; throw clearly if absent
                put("password", obfsPassword
                    ?: throw IllegalArgumentException("hysteria2: obfs-password required when obfs=$obfsType"))
            })
        }

        val streamSettings = JSONObject().apply {
            put("network", "tcp")        // Hysteria2 encapsulates its own QUIC; outer is tcp
            put("security", "tls")
            put("tlsSettings", JSONObject().apply {
                put("serverName", sni)
                put("allowInsecure", allowInsecure)
            })
        }

        return JSONObject().apply {
            put("protocol", "hysteria2")
            put("settings", JSONObject().put("servers", JSONArray().put(hy2Settings)))
            put("streamSettings", streamSettings)
        }
    }

    // ── STREAM SETTINGS ────────────────────────────────────────────────────
    /**
     * Builds the streamSettings block shared by VLESS, VMess, and Trojan.
     *
     * @param network   Transport type: tcp / ws / grpc / http / h2
     * @param security  TLS mode:       none / tls / reality
     * @param sni       TLS server name (used in both tls and reality)
     * @param params    Decoded query params from the URI (or VMess JSON extras)
     */
    private fun buildStreamSettings(
        network:  String,
        security: String,
        sni:      String,
        params:   Map<String, String>
    ): JSONObject = JSONObject().apply {

        put("network", network)
        put("security", security)

        // ── TLS / Reality ────────────────────────────────────────────────
        when (security) {
            "tls" -> put("tlsSettings", JSONObject().apply {
                put("serverName", sni)
                put("allowInsecure", false)
            })
            "reality" -> put("realitySettings", JSONObject().apply {
                put("serverName", sni)
                put("fingerprint", params["fp"]  ?: "chrome")
                put("shortId",     params["sid"] ?: "")
                put("publicKey",   params["pbk"] ?: "")
                put("spiderX",     params["spx"] ?: "")
            })
        }

        // ── Transport ────────────────────────────────────────────────────
        when (network) {
            "ws" -> put("wsSettings", JSONObject().apply {
                put("path", params["path"] ?: "/")
                put("headers", JSONObject().put("Host", params["host"] ?: sni))
            })
            "grpc" -> put("grpcSettings", JSONObject().apply {
                // serviceName can come from serviceName or the path param (some clients use path)
                put("serviceName", params["serviceName"] ?: params["path"] ?: "")
            })
            "http", "h2" -> put("httpSettings", JSONObject().apply {
                put("path", params["path"] ?: "/")
                put("host", JSONArray().put(params["host"] ?: sni))
            })
            // FIX: VMess over TCP with HTTP obfuscation (type=http in VMess JSON).
            // This is distinct from network="http" — the outer transport is TCP but
            // each frame is wrapped in an HTTP/1.1 header. libv2ray expects
            // tcpSettings.header.type = "http" for this case.
            "tcp" -> {
                val headerType = params["headerType"] ?: "none"
                if (headerType == "http") {
                    put("tcpSettings", JSONObject().apply {
                        put("header", JSONObject().apply {
                            put("type", "http")
                            // A request block is needed for the HTTP obfuscation headers
                            put("request", JSONObject().apply {
                                put("version", "1.1")
                                put("method", "GET")
                                put("path", JSONArray().put(params["path"] ?: "/"))
                                put("headers", JSONObject().apply {
                                    put("Host", JSONArray().put(params["host"] ?: sni))
                                    put("User-Agent", JSONArray().put(
                                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
                                        "AppleWebKit/537.36 (KHTML, like Gecko) " +
                                        "Chrome/124.0.0.0 Safari/537.36"
                                    ))
                                    put("Accept-Encoding", JSONArray().put("gzip, deflate"))
                                    put("Connection", JSONArray().put("keep-alive"))
                                    put("Pragma", JSONArray().put("no-cache"))
                                })
                            })
                        })
                    })
                }
                // type=none → plain TCP, no extra settings needed
            }
        }
    }

    // ── HELPERS ────────────────────────────────────────────────────────────

    /**
     * Splits "host:port" correctly for both IPv4 and IPv6.
     *
     * IPv6 addresses are wrapped in brackets: [2001:db8::1]:443
     * Using lastIndexOf(":") alone would land inside the bracket group,
     * so we detect and strip the brackets explicitly.
     *
     * @return Pair(host, port) — host is unwrapped (no square brackets)
     */
    private fun splitHostPort(hostPort: String, scheme: String): Pair<String, Int> {
        return if (hostPort.startsWith("[")) {
            // IPv6: format is [addr]:port
            val closeBracket = hostPort.indexOf("]")
            if (closeBracket < 0) throw IllegalArgumentException("$scheme: unclosed '[' in host")
            val host = hostPort.substring(1, closeBracket)          // strip brackets
            val portStr = hostPort.substring(closeBracket + 2)      // skip "]:"
            val port = portStr.toIntOrNull()
                ?: throw IllegalArgumentException("$scheme: invalid port '$portStr'")
            host to port
        } else {
            // IPv4 / hostname: split on last colon
            val lastColon = hostPort.lastIndexOf(":")
            if (lastColon < 0) throw IllegalArgumentException("$scheme: missing port in '$hostPort'")
            val host    = hostPort.substring(0, lastColon)
            val portStr = hostPort.substring(lastColon + 1)
            val port    = portStr.toIntOrNull()
                ?: throw IllegalArgumentException("$scheme: invalid port '$portStr'")
            host to port
        }
    }

    /**
     * Guards against java.net.URI returning -1 when no port is present in the URI.
     * Throwing here gives a clear error rather than passing -1 silently to libv2ray.
     */
    private fun requirePort(port: Int, scheme: String): Int {
        if (port < 0) throw IllegalArgumentException("$scheme: port is missing or invalid")
        return port
    }

    /**
     * Decodes "0"/"1" / "true"/"false" / "yes"/"no" param values to Boolean.
     * Defaults to false when the param is absent or unrecognised.
     */
    private fun parseBoolParam(value: String?): Boolean = when (value?.lowercase()) {
        "1", "true", "yes" -> true
        else               -> false
    }

    /**
     * Parses a URL query string into a Map.
     * Both keys and values are URL-decoded.
     * When a key appears multiple times, the last value wins
     * (sufficient for proxy URIs where duplicate keys are not meaningful).
     */
    private fun parseQuery(query: String?): Map<String, String> {
        if (query.isNullOrEmpty()) return emptyMap()
        return query.split("&").mapNotNull { pair ->
            val eq = pair.indexOf("=")
            if (eq < 0) null    // skip malformed key-only params
            else {
                val key = java.net.URLDecoder.decode(pair.substring(0, eq), "UTF-8")
                val value = java.net.URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
                key to value
            }
        }.toMap()
    }

    /**
     * Decodes a base64 string, normalising URL-safe characters and padding.
     * Handles both standard (+/) and URL-safe (-_) alphabets.
     */
    private fun decodeBase64(s: String): String {
        val normalised = s
            .replace("-", "+")
            .replace("_", "/")
            .let { it + "=".repeat((4 - it.length % 4) % 4) }   // re-add stripped padding
        return String(Base64.decode(normalised, Base64.DEFAULT))
    }

    /** Same as decodeBase64 but returns null instead of throwing on malformed input. */
    private fun decodeBase64Safe(s: String): String? = try {
        decodeBase64(s)
    } catch (e: Exception) {
        null
    }
}
