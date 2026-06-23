package ir.proxysmith.proxysmith_flutter

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

data class Candidate(
    val uri: String,
    val ms: Long,       // -1 = failed
    val error: String = ""
)

object Pipeline {

    /**
     * Runs the full 3-round elimination pipeline.
     *
     * @param uris        Sampled URI list from SubscriptionFetcher
     * @param concurrency Round 1 concurrency (default 20)
     * @param maxPingMs   Round 1 hard cutoff in ms (0 = no limit)
     * @param testUrl     URL to measure against
     * @param onProgress  Called after each URI is tested: (done, total, round)
     * @return Top 10 candidates sorted by latency ascending
     */
    suspend fun run(
        uris: List<String>,
        concurrency: Int = 20,
        maxPingMs: Long = 8000L,
        testUrl: String = "https://www.google.com/generate_204",
        onProgress: ((done: Int, total: Int, round: Int) -> Unit)? = null
    ): List<Candidate> {

        // Round 1: full sampled list, high concurrency, hard ping cutoff
        val r1 = runRound(
            label = "Round 1",
            uris = uris,
            concurrency = concurrency,
            keepTop = 60,
            maxPingMs = maxPingMs,
            testUrl = testUrl,
            round = 1,
            onProgress = onProgress
        )

        if (r1.isEmpty()) return emptyList()

        // Round 2: survivors, moderate concurrency, no ping cutoff
        val r2 = runRound(
            label = "Round 2",
            uris = r1.map { it.uri },
            concurrency = 5,
            keepTop = 30,
            maxPingMs = 0L,
            testUrl = testUrl,
            round = 2,
            onProgress = onProgress
        )

        if (r2.isEmpty()) return emptyList()

        // Round 3: single-threaded, most honest measurement
        val r3 = runRound(
            label = "Round 3",
            uris = r2.map { it.uri },
            concurrency = 1,
            keepTop = 10,
            maxPingMs = 0L,
            testUrl = testUrl,
            round = 3,
            onProgress = onProgress
        )

        return r3
    }

    // ── SINGLE ROUND ───────────────────────────────────────────────────────
    private suspend fun runRound(
        label: String,
        uris: List<String>,
        concurrency: Int,
        keepTop: Int,
        maxPingMs: Long,
        testUrl: String,
        round: Int,
        onProgress: ((Int, Int, Int) -> Unit)?
    ): List<Candidate> = coroutineScope {

        val semaphore = Semaphore(concurrency)
        val done = java.util.concurrent.atomic.AtomicInteger(0)
        val total = uris.size

        val results: List<Candidate> = uris.map { uri ->
            async(Dispatchers.IO) {
                semaphore.withPermit {
                    val candidate = testUri(uri, testUrl)
                    val d = done.incrementAndGet()
                    onProgress?.invoke(d, total, round)
                    candidate
                }
            }
        }.awaitAll()

        // Filter: keep only passing results within ping cutoff
        val passing = results.filter { c ->
            c.ms > 0 && (maxPingMs <= 0 || c.ms <= maxPingMs)
        }

        // Sort by latency, keep top N
        passing.sortedBy { it.ms }.take(keepTop)
    }

    // ── SINGLE URI TEST ────────────────────────────────────────────────────
    private fun testUri(uri: String, testUrl: String): Candidate {
        val outbound = try {
            UriParser.parseURIToOutbound(uri)
        } catch (e: Exception) {
            return Candidate(uri, -1, "parse error: ${e.message}")
        }

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
