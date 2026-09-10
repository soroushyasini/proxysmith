package ir.proxysmith.proxysmith_flutter

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull

class UriParserTest {
    @Test
    fun `malformed supported URIs return errors`() {
        for (uri in listOf(
            "ss://not-valid@example.com:443",
            "vless://example.com:443",
            "trojan://secret@example.com"
        )) {
            assertFailsWith<IllegalArgumentException> {
                UriParser.parseURIToOutbound(uri)
            }
        }
    }

    @Test
    fun `vless grpc and xhttp transports use pinned Xray names`() {
        val grpc = UriParser.parseURIToOutbound(
            "vless://id@example.com:443?security=tls&type=grpc&serviceName=svc"
        ).getJSONObject("streamSettings")
        assertEquals("grpc", grpc.getString("network"))
        assertEquals("svc", grpc.getJSONObject("grpcSettings").getString("serviceName"))

        val xhttp = UriParser.parseURIToOutbound(
            "vless://id@example.com:443?security=tls&type=xhttp&path=%2Fapi&host=edge.example"
        ).getJSONObject("streamSettings")
        assertEquals("splithttp", xhttp.getString("network"))
        assertNotNull(xhttp.getJSONObject("splithttpSettings"))
    }

    @Test
    fun `hysteria2 uses pinned Xray outbound shape`() {
        val outbound = UriParser.parseURIToOutbound(
            "hysteria2://secret@example.com:443?sni=edge.example&insecure=1"
        )

        assertEquals("hysteria", outbound.getString("protocol"))
        assertEquals(2, outbound.getJSONObject("settings").getInt("version"))
        val stream = outbound.getJSONObject("streamSettings")
        assertEquals("hysteria", stream.getString("network"))
        assertEquals("secret", stream.getJSONObject("hysteriaSettings").getString("auth"))
    }
}
