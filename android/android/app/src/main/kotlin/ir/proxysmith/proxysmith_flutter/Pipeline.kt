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

// Change #5 — partial-result event type
// When a round throws unexpectedly (OOM, libv2ray hang, etc.), we don't
// want to lose all work. The pipeline catches the exception, fires this
// event so the UI can show a warning banner, and returns whatever the
// last successful round produced (top 10).
data class PipelineWarning(val message: String, val partialResults: List<Candidate>)

object Pipeline {

    private val DEFAULT_CONCURRENCY = minOf(
        Runtime.getRuntime().availableProcessors() * 2,
        32
    )

    private const val PROGRESS_THROTTLE_MS = 100L
    private const val TCP_PRECHECK_MS      = 1_000

    // Change #1 — QUIC protocol schemes that must skip the TCP pre-check.
    // TUIC and Hysteria2 run over QUIC/UDP. A TCP socket connect to their
    // host:port will always fail because there is no TCP listener.
    // The pre-check is only meaningful for TCP-based protocols (VMess, VLESS,
    // Trojan, Shadowsocks). Skipping it for QUIC protocols means they go
    // straight to libv2ray measurement — which uses QUIC internally.
    private val QUIC_SCHEMES = setOf("tuic", "hysteria2", "hy2")

    // Change #3 — Round 3 retry: when both attempts succeed, we take the
    // average (more honest than minimum, which v2rayNG uses). If the retry
    // fails, we keep the first result unchanged — one bad sample is still
    // better than nothing.
    private const val ROUND3_RETRY_DELAY_MS = 200L   // brief pause before retry

    // Change #8 — Round 3 hard cap.
    // With concurrency=1 and up to 30 URIs, worst case without a cap is
    // 30 × 12_000ms = 360s. We cap the entire round at 90s — generous
    // enough for 30 URIs but prevents runaway hangs if libv2ray freezes.
    private const val ROUND3_HARD_CAP_MS = 90_000L

    // ── PUBLIC API ─────────────────────────────────────────────────────────

    /**
     * Runs the full 3-round elimination pipeline.
     *
     * Change #5: if any round after Round 1 throws, the exception is caught,
     * a [PipelineWarning] is delivered via [onWarning], and the best available
     * results (top 10 of the last successful round) are returned instead of
     * propagating the error and returning nothing.
     *
     * @param uris        Sampled URI list from SubscriptionFetcher
     * @param concurrency Concurrent test slots (default = CPU cores × 2, max 32)
     * @param maxPingMs   Round 1 hard cutoff in ms (0 = no limit)
     * @param testUrl     URL to measure latency against
     * @param onProgress  Called after each URI is tested: (done, total, round)
     * @param onWarning   Called when a round fails and partial results are returned
     * @return Top 10 candidates sorted by latency ascending
     */
    suspend fun run(
        uris:        List<String>,
        concurrency: Int    = DEFAULT_CONCURRENCY,
        maxPingMs:   Long   = 8000L,
        testUrl:     String = "https://www.google.com/generate_204",
        onProgress:  ((done: Int, total: Int, round: Int) -> Unit)? = null,
        onWarning:   ((PipelineWarning) -> Unit)?                   = null
    ): List<Candidate> {

        // Round 1 — elimination at scale. If this throws, let it propagate —
        // there's nothing to return yet.
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

        // Change #5 — partial-result safety net for Round 2 and Round 3.
        // If either round throws after Round 1 succeeded, we catch the
        // exception, fire a warning, and fall back to top 10 of r1.
        // "Simplicity" variant: always return top 10 of the last good round.

        // Round 2
        val r2: List<Candidate> = if (r1.size <= 30) {
            r1
        } else {
            try {
                runRound(
                    uris        = r1.map { it.uri },
                    concurrency = 5,
                    keepTop     = 30,
                    maxPingMs   = 0L,
                    testUrl     = testUrl,
                    round       = 2,
                    onProgress  = onProgress
                )
            } catch (e: CancellationException) {
                throw e   // user-initiated stop — let it propagate normally
            } catch (e: Exception) {
                val partial = r1.take(10)
                onWarning?.invoke(PipelineWarning(
                    message        = "Round 2 failed (${e.message}); returning top 10 from Round 1",
                    partialResults = partial
                ))
                return partial
            }
        }
        if (r2.isEmpty()) return r1.take(10)

        // Round 3 — Change #8: wrapped in a hard cap timeout
        return if (r2.size <= 10) {
            r2.take(10)
        } else {
            try {
                withTimeout(ROUND3_HARD_CAP_MS) {
                    runRound(
                        uris        = r2.map { it.uri },
                        concurrency = 1,
                        keepTop     = 10,
                        maxPingMs   = 0L,
                        testUrl     = testUrl,
                        round       = 3,
                        onProgress  = onProgress,
                        isRound3    = true   // Change #3: enables per-URI retry
                    )
                }
            } catch (e: CancellationException) {
                // Could be user stop OR the hard-cap timeout firing.
                // Distinguish: TimeoutCancellationException is a subtype of CancellationException.
                if (e is TimeoutCancellationException) {
                    val partial = r2.take(10)
                    onWarning?.invoke(PipelineWarning(
                        message        = "Round 3 exceeded ${ROUND3_HARD_CAP_MS / 1000}s cap; returning top 10 from Round 2",
                        partialResults = partial
                    ))
                    partial
                } else {
                    throw e   // genuine user stop — propagate
                }
            } catch (e: Exception) {
                val partial = r2.take(10)
                onWarning?.invoke(PipelineWarning(
                    message        = "Round 3 failed (${e.message}); returning top 10 from Round 2",
                    partialResults = partial
                ))
                partial
            }
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
        onProgress:  ((Int, Int, Int) -> Unit)?,
        isRound3:    Boolean = false   // Change #3
    ): List<Candidate> = coroutineScope {

        val semaphore    = Semaphore(concurrency)
        val done         = AtomicInteger(0)
        val passingCount = AtomicInteger(0)
        val total        = uris.size

        val timeoutMs = if (maxPingMs > 0) maxPingMs + 2_000L else 12_000L
        val lastProgressAt = AtomicLong(0L)

        val results: List<Candidate> = uris.map { uri ->
            async(Dispatchers.IO) {
                semaphore.withPermit {
                    if (passingCount.get() >= keepTop) {
                        val d = done.incrementAndGet()
                        maybeReportProgress(lastProgressAt, onProgress, d, total, round)
                        return@withPermit null
                    }

                    val candidate = withTimeoutOrNull(timeoutMs) {
                        testUri(uri, testUrl, maxPingMs, isRound3)
                    } ?: Candidate(uri, -1, "timeout after ${timeoutMs}ms")

                    val isPassing = candidate.ms > 0 && (maxPingMs <= 0 || candidate.ms <= maxPingMs)
                    if (isPassing) passingCount.incrementAndGet()

                    val d = done.incrementAndGet()
                    maybeReportProgress(lastProgressAt, onProgress, d, total, round)

                    candidate
                }
            }
        }.awaitAll()
            .filterNotNull()

        results
            .filter { c -> c.ms > 0 && (maxPingMs <= 0 || c.ms <= maxPingMs) }
            .sortedBy { it.ms }
            .take(keepTop)
    }

    // ── SINGLE URI TEST ────────────────────────────────────────────────────

    /**
     * Tests one URI and returns its latency.
     *
     * Change #1: QUIC-based protocols (tuic, hysteria2, hy2) skip the TCP
     * pre-check entirely. They have no TCP listener — the pre-check would
     * always return false and incorrectly eliminate valid QUIC proxies.
     *
     * Change #3: when [isRound3] is true, a single retry is performed after
     * a brief pause. If both attempts succeed, the average is returned
     * (more honest than minimum). If the retry fails, the first result stands.
     */
    private fun testUri(
        uri:      String,
        testUrl:  String,
        maxPingMs: Long,
        isRound3: Boolean = false
    ): Candidate {

        val firstResult = testUriOnce(uri, testUrl)

        // Change #3 — Round 3 retry (average of two attempts)
        if (isRound3 && firstResult.ms > 0) {
            Thread.sleep(ROUND3_RETRY_DELAY_MS)
            val retryResult = testUriOnce(uri, testUrl)
            if (retryResult.ms > 0) {
                val avg = (firstResult.ms + retryResult.ms) / 2
                return Candidate(uri, avg)
            }
            // Retry failed — first result stands, no penalty
        }

        return firstResult
    }

    /**
     * Single measurement attempt for one URI.
     * Separated from [testUri] so the retry in Round 3 reuses this cleanly.
     */
    private fun testUriOnce(uri: String, testUrl: String): Candidate {

        // Step 1: parse URI → outbound config
        val outbound = try {
            UriParser.parseURIToOutbound(uri)
        } catch (e: Exception) {
            val scheme = uri.substringBefore("://").ifEmpty { "unknown" }
            return Candidate(uri, -1, "[$scheme] parse error: ${e.message}")
        }

        // Step 2: TCP pre-check — Change #1: skip for QUIC protocols
        val scheme = uri.substringBefore("://").lowercase()
        val isQuic = scheme in QUIC_SCHEMES

        if (!isQuic) {
            // Only run TCP pre-check for TCP-based protocols
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
        }
        // QUIC protocols: skip TCP pre-check, go straight to libv2ray measurement

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
        if (done == total || now - last >= PROGRESS_THROTTLE_MS) {
            if (lastProgressAt.compareAndSet(last, now)) {
                onProgress(done, total, round)
            }
        }
    }
}
