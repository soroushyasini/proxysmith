package ir.proxysmith.proxysmith_flutter

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

data class Candidate(
    val uri:   String,
    val ms:    Long,        // -1 = failed / timed-out
    val error: String = ""  // human-readable reason for failures
)

object Pipeline {

    /**
     * Runs the full 3-round elimination pipeline.
     *
     * Round 1 — full sampled list, high concurrency, hard ping cutoff.
     *           Keeps the top 60 fastest.
     * Round 2 — survivors only, moderate concurrency, no cutoff.
     *           Keeps the top 30.
     * Round 3 — single-threaded, most honest/stable measurement.
     *           Keeps the top 10.
     *
     * @param uris        Sampled URI list from SubscriptionFetcher
     * @param concurrency Round 1 concurrency (default 20)
     * @param maxPingMs   Round 1 hard cutoff in ms (0 = no limit)
     * @param testUrl     URL to measure against
     * @param onProgress  Called after each URI is tested: (done, total, round)
     * @return Top 10 candidates sorted by latency ascending
     */
    suspend fun run(
        uris:        List<String>,
        concurrency: Int    = 20,
        maxPingMs:   Long   = 8000L,
        testUrl:     String = "https://www.google.com/generate_204",
        onProgress:  ((done: Int, total: Int, round: Int) -> Unit)? = null
    ): List<Candidate> {

        // Round 1
        val r1 = runRound(
            uris        = uris,
            concurrency = concurrency,
            keepTop     = 60,
            maxPingMs   = maxPingMs,
            testUrl     = testUrl,
            round       = 1,
            onProgress  = onProgress
        )
        if (r1.isEmpty()) return emptyList()

        // Round 2
        val r2 = runRound(
            uris        = r1.map { it.uri },
            concurrency = 5,
            keepTop     = 30,
            maxPingMs   = 0L,
            testUrl     = testUrl,
            round       = 2,
            onProgress  = onProgress
        )
        if (r2.isEmpty()) return emptyList()

        // Round 3
        return runRound(
            uris        = r2.map { it.uri },
            concurrency = 1,
            keepTop     = 10,
            maxPingMs   = 0L,
            testUrl     = testUrl,
            round       = 3,
            onProgress  = onProgress
        )
    }

    // ── SINGLE ROUND ───────────────────────────────────────────────────────
    private suspend fun runRound(
        uris:       List<String>,
        concurrency: Int,
        keepTop:    Int,
        maxPingMs:  Long,
        testUrl:    String,
        round:      Int,
        onProgress: ((Int, Int, Int) -> Unit)?
    ): List<Candidate> = coroutineScope {

        val semaphore = Semaphore(concurrency)
        val done      = java.util.concurrent.atomic.AtomicInteger(0)
        val total     = uris.size

        // Per-URI timeout: give maxPingMs + 2 s grace so the cutoff fires
        // before the coroutine timeout, or a flat 12 s cap for rounds 2 & 3.
        val timeoutMs = if (maxPingMs > 0) maxPingMs + 2_000L else 12_000L

        val results: List<Candidate> = uris.map { uri ->
            async(Dispatchers.IO) {
                semaphore.withPermit {
                    // withTimeoutOrNull ensures a single hanging proxy can't
                    // stall the whole round indefinitely
                    val candidate = withTimeoutOrNull(timeoutMs) {
                        testUri(uri, testUrl)
                    } ?: Candidate(uri, -1, "timeout after ${timeoutMs}ms")

                    val d = done.incrementAndGet()
                    onProgress?.invoke(d, total, round)
                    candidate
                }
            }
        }.awaitAll()

        // Keep only successful measurements within the ping cutoff
        results
            .filter { c -> c.ms > 0 && (maxPingMs <= 0 || c.ms <= maxPingMs) }
            .sortedBy { it.ms }
            .take(keepTop)
    }

    // ── SINGLE URI TEST ────────────────────────────────────────────────────
    private fun testUri(uri: String, testUrl: String): Candidate {
        // Step 1: parse URI → libv2ray outbound config JSON
        val outbound = try {
            UriParser.parseURIToOutbound(uri)
        } catch (e: Exception) {
            // Include the URI scheme in the error so logs are easier to triage
            val scheme = uri.substringBefore("://").ifEmpty { "unknown" }
            return Candidate(uri, -1, "[$scheme] parse error: ${e.message}")
        }

        // Step 2: wrap in a minimal v2ray config and measure latency
        val configJson = """
        {
          "log": { "loglevel": "none" },
          "outbounds": [$outbound]
        }
        """.trimIndent()

        return try {
            val ms = libv2ray.Libv2ray.measureOutboundDelay(configJson, testUrl)
            Candidate(uri, ms)
        } catch (e: Exception) {
            Candidate(uri, -1, "measure error: ${e.message}")
        }
    }
}
