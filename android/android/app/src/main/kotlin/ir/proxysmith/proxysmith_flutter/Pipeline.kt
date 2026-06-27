package ir.proxysmith.proxysmith_flutter

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

data class Candidate(
    val uri:   String,
    val ms:    Long,        // -1 = failed / timed-out
    val error: String = "" // human-readable reason, populated on failure
)

object Pipeline {

    /**
     * Adaptive concurrency ceiling.
     *
     * v2rayNG confirms measureOutboundDelay is thread-safe (it uses its own
     * newFixedThreadPool with no external lock). We scale to CPU count but
     * cap at 32 to avoid saturating the phone's network stack.
     *
     * Typical phones: 8 cores → 16 concurrent tests.
     */
    private val DEFAULT_CONCURRENCY = minOf(
        Runtime.getRuntime().availableProcessors() * 2,
        32
    )

    /**
     * How often (in ms) we forward progress events to Flutter.
     *
     * At concurrency=16 we can fire 16 events almost simultaneously.
     * Throttling to 100ms prevents rapid-fire setState() calls that cause
     * UI jank, while still giving smooth enough progress feedback.
     */
    private const val PROGRESS_THROTTLE_MS = 100L

    /**
     * TCP pre-check timeout in ms.
     *
     * Borrowed from v2rayNG's RealPingWorkerService: attempt a raw TCP
     * connect before invoking libv2ray. Dead hosts fail here in ~1s instead
     * of burning the full maxPingMs timeout in libv2ray. This alone can cut
     * Round 1 time by 40–60% on subscription lists where many proxies are offline.
     */
    private const val TCP_PRECHECK_MS = 1_000

    // ── PUBLIC API ─────────────────────────────────────────────────────────

    /**
     * Runs the full 3-round elimination pipeline.
     *
     * Round 1 — full sampled list, adaptive concurrency, hard ping cutoff.
     *           Keeps up to 60 fastest. Exits early once 60 passing results
     *           are collected — remaining jobs are cancelled immediately.
     * Round 2 — survivors, moderate concurrency, no cutoff. Keeps up to 30.
     *           Skipped if Round 1 already returned ≤ 30 results.
     * Round 3 — single-threaded, most honest/stable measurement. Keeps top 10.
     *           Skipped if Round 2 already returned ≤ 10 results.
     *
     * @param uris        Sampled URI list from SubscriptionFetcher
     * @param concurrency Concurrent test slots (default = CPU cores × 2, max 32)
     * @param maxPingMs   Round 1 hard cutoff in ms (0 = no limit)
     * @param testUrl     URL to measure latency against
     * @param onProgress  Called after each URI is tested: (done, total, round)
     * @return Top 10 candidates sorted by latency ascending
     */
    suspend fun run(
        uris:        List<String>,
        concurrency: Int    = DEFAULT_CONCURRENCY,
        maxPingMs:   Long   = 8000L,
        testUrl:     String = "https://www.google.com/generate_204",
        onProgress:  ((done: Int, total: Int, round: Int) -> Unit)? = null
    ): List<Candidate> {

        // Round 1 — elimination at scale
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

        // Round 2 — skip if Round 1 already gave us a small enough set
        val r2 = if (r1.size <= 30) {
            r1   // already ≤ keepTop for Round 2, no need to re-test
        } else {
            runRound(
                uris        = r1.map { it.uri },
                concurrency = 5,
                keepTop     = 30,
                maxPingMs   = 0L,
                testUrl     = testUrl,
                round       = 2,
                onProgress  = onProgress
            )
        }
        if (r2.isEmpty()) return emptyList()

        // Round 3 — skip if Round 2 already gave us ≤ 10 results
        return if (r2.size <= 10) {
            r2.take(10)
        } else {
            runRound(
                uris        = r2.map { it.uri },
                concurrency = 1,
                keepTop     = 10,
                maxPingMs   = 0L,
                testUrl     = testUrl,
                round       = 3,
                onProgress  = onProgress
            )
        }
    }

    // ── SINGLE ROUND ───────────────────────────────────────────────────────

    private suspend fun runRound(
        uris:        List<String>,
        concurrency: Int,
        keepTop:     Int,
        maxPingMs:   Long,
        testUrl:     String,
        round:       Int,
        onProgress:  ((Int, Int, Int) -> Unit)?
    ): List<Candidate> = coroutineScope {

        val semaphore    = Semaphore(concurrency)
        val done         = AtomicInteger(0)
        val passingCount = AtomicInteger(0)
        val total        = uris.size

        // Per-URI hard timeout: ping cutoff + 2s grace, or 12s flat for
        // rounds 2 & 3 where maxPingMs = 0.
        val timeoutMs = if (maxPingMs > 0) maxPingMs + 2_000L else 12_000L

        // Throttle: track when we last forwarded a progress event so we don't
        // fire setState() dozens of times per second from concurrent completions.
        val lastProgressAt = AtomicLong(0L)

        // Early-exit gate: once we have enough passing results we set this
        // so new jobs skip libv2ray work and cancel themselves cheaply.
        // Using a coroutine Job lets us cancel all children in one call.
        val roundScope = this

        val results: List<Candidate> = uris.map { uri ->
            async(Dispatchers.IO) {
                semaphore.withPermit {
                    // ── Early exit check ──────────────────────────────────
                    // If we already have enough passing results, don't bother
                    // starting a new libv2ray measurement — just count as done
                    // and report progress so the UI bar keeps moving.
                    if (passingCount.get() >= keepTop) {
                        val d = done.incrementAndGet()
                        maybeReportProgress(lastProgressAt, onProgress, d, total, round)
                        return@withPermit null   // null = skipped, filtered out below
                    }

                    val candidate = withTimeoutOrNull(timeoutMs) {
                        testUri(uri, testUrl, maxPingMs)
                    } ?: Candidate(uri, -1, "timeout after ${timeoutMs}ms")

                    // Track how many passing results we have so far
                    val isPassing = candidate.ms > 0 && (maxPingMs <= 0 || candidate.ms <= maxPingMs)
                    if (isPassing) passingCount.incrementAndGet()

                    val d = done.incrementAndGet()
                    maybeReportProgress(lastProgressAt, onProgress, d, total, round)

                    candidate
                }
            }
        }.awaitAll()
            .filterNotNull()   // remove skipped (early-exit) slots

        // Keep only passing measurements, sort by latency, return top N
        results
            .filter { c -> c.ms > 0 && (maxPingMs <= 0 || c.ms <= maxPingMs) }
            .sortedBy { it.ms }
            .take(keepTop)
    }

    // ── SINGLE URI TEST ────────────────────────────────────────────────────

    /**
     * Tests one URI and returns its latency.
     *
     * Mirrors v2rayNG's RealPingWorkerService.startRealPing():
     *   1. TCP pre-check  — cheap 1s socket connect to filter dead hosts
     *   2. libv2ray test  — full HTTP measurement only if TCP succeeded
     *
     * This two-stage approach is the single biggest throughput win on
     * real subscription lists where 30–60% of proxies are offline.
     */
    private fun testUri(uri: String, testUrl: String, maxPingMs: Long): Candidate {

        // Step 1: parse URI → outbound config
        val outbound = try {
            UriParser.parseURIToOutbound(uri)
        } catch (e: Exception) {
            val scheme = uri.substringBefore("://").ifEmpty { "unknown" }
            return Candidate(uri, -1, "[$scheme] parse error: ${e.message}")
        }

        // Step 2: TCP pre-check — extract host/port from the outbound JSON
        // and attempt a raw socket connect. If this fails, the proxy is
        // definitely dead and we skip the heavier libv2ray call entirely.
        val host = outbound.optJSONObject("settings")
            ?.optJSONArray("vnext")?.optJSONObject(0)?.optString("address")
            ?: outbound.optJSONObject("settings")
                ?.optJSONArray("servers")?.optJSONObject(0)?.optString("address")

        val port = outbound.optJSONObject("settings")
            ?.optJSONArray("vnext")?.optJSONObject(0)?.optInt("port", -1)
            ?: outbound.optJSONObject("settings")
                ?.optJSONArray("servers")?.optJSONObject(0)?.optInt("port", -1)
            ?: -1

        if (!host.isNullOrEmpty() && port > 0) {
            val tcpOk = tcpConnect(host, port, TCP_PRECHECK_MS)
            if (!tcpOk) {
                return Candidate(uri, -1, "tcp pre-check failed (host unreachable)")
            }
        }

        // Step 3: full libv2ray latency measurement
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

    // ── HELPERS ────────────────────────────────────────────────────────────

    /**
     * Attempts a raw TCP connect to [host]:[port] within [timeoutMs].
     * Returns true if the connection succeeds, false on any failure.
     *
     * This is intentionally low-level — we just want to know if the host
     * is reachable at all before spending time on a full HTTP measurement.
     */
    private fun tcpConnect(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Forwards a progress event to Flutter, but at most once per
     * [PROGRESS_THROTTLE_MS] milliseconds.
     *
     * Without throttling, 16 concurrent jobs completing within the same
     * millisecond would fire 16 rapid setState() calls on the Flutter side,
     * causing visible UI jank on the progress bar.
     */
    private fun maybeReportProgress(
        lastProgressAt: AtomicLong,
        onProgress:     ((Int, Int, Int) -> Unit)?,
        done:           Int,
        total:          Int,
        round:          Int
    ) {
        if (onProgress == null) return
        val now  = System.currentTimeMillis()
        val last = lastProgressAt.get()
        // Always report the final completion (done == total) regardless of throttle
        if (done == total || now - last >= PROGRESS_THROTTLE_MS) {
            if (lastProgressAt.compareAndSet(last, now)) {
                onProgress(done, total, round)
            }
        }
    }
}
