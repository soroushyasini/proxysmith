package ir.proxysmith.proxysmith_flutter

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class SubscriptionFetcherTest {
    @Test
    fun `normalization deduplicates before selecting exact count`() {
        val lines = listOf(
            "vless://id@one.example:443#one",
            "vless://id@one.example:443#renamed",
            "ss://method:pass@two.example:8388",
            "trojan://pass@three.example:443",
            "vmess://payload",
            "tuic://id:pass@unsupported.example:443"
        )

        val selected = SubscriptionFetcher.selectSupportedUris(lines, 3, Random(7))

        assertEquals(3, selected.size)
        assertEquals(3, selected.map { it.substringBefore("#") }.toSet().size)
        assertFalse(selected.any { it.startsWith("tuic://") })
    }

    @Test
    fun `selection rejects a proxy URI longer than the line safety limit`() {
        val oversized = "vless://" + "a".repeat(64 * 1024)

        assertEquals(
            emptyList(),
            SubscriptionFetcher.selectSupportedUris(listOf(oversized), testCount = 1)
        )
    }
}
