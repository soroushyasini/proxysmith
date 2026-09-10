package ir.proxysmith.proxysmith_flutter

import android.os.SystemClock
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

data class Candidate(
    val uri: String,
    val ms: Long,
    val jitterMs: Long = 0,
    val successes: Int = 0,
    val attempts: Int = 0,
    val inputIndex: Int = 0,
    val error: String = ""
)

data class PipelineWarning(val message: String, val partialResults: List<Candidate>)

internal class ProgressReporter(private val intervalMs: Long = 100) {
    private val lastEmissionMs = AtomicLong(0)

    fun shouldEmit(completed: Int, total: Int, nowMs: Long): Boolean {
        if (completed >= total) return true
        while (true) {
            val previous = lastEmissionMs.get()
            if (nowMs - previous < intervalMs) return false
            if (lastEmissionMs.compareAndSet(previous, nowMs)) return true
        }
    }
}

object Pipeline {
    private const val defaultConcurrency = 20
    private const val tcpPrecheckMs = 1_000
    private const val round3HardCapMs = 120_000L
    private val udpSchemes = setOf("hysteria2", "hy2")

    suspend fun run(
        uris: List<String>,
        concurrency: Int = defaultConcurrency,
        maxPingMs: Long = 8_000L,
        testUrl: String = "https://cp.cloudflare.com/generate_204",
        onProgress: ((done: Int, total: Int, round: Int) -> Unit)? = null,
        onWarning: ((PipelineWarning) -> Unit)? = null
    ): List<Candidate> {
        val first = runRound(uris, concurrency.coerceIn(1, 60), 60, maxPingMs, testUrl, 1, onProgress)
        if (first.isEmpty()) return emptyList()
        val second = try {
            runRound(first.map { it.uri }, minOf(5, concurrency.coerceAtLeast(1)), 30, 0, testUrl, 2, onProgress)
        } catch (exception: CancellationException) {
            throw exception
        } catch (exception: Exception) {
            return partial(first, 2, exception, onWarning)
        }
        if (second.isEmpty()) return first.take(10)
        return try {
            withTimeout(round3HardCapMs) {
                runRound(second.map { it.uri }, 1, 10, 0, testUrl, 3, onProgress)
            }
        } catch (exception: CancellationException) {
            if (exception is TimeoutCancellationException) {
                onWarning?.invoke(PipelineWarning("Round 3 exceeded its safety limit; returning Round 2 results", second.take(10)))
                second.take(10)
            } else {
                throw exception
            }
        } catch (exception: Exception) {
            partial(second, 3, exception, onWarning)
        }
    }

    private suspend fun runRound(
        uris: List<String>,
        concurrency: Int,
        keepTop: Int,
        maxPingMs: Long,
        testUrl: String,
        round: Int,
        onProgress: ((Int, Int, Int) -> Unit)?
    ): List<Candidate> = coroutineScope {
        if (uris.isEmpty()) return@coroutineScope emptyList()
        val jobs = Channel<Int>(concurrency)
        val results = arrayOfNulls<Candidate>(uris.size)
        val done = AtomicInteger(0)
        val progressReporter = ProgressReporter()
        val workerCount = minOf(concurrency.coerceAtLeast(1), uris.size)
        repeat(workerCount) {
            launch(Dispatchers.IO) {
                for (index in jobs) {
                    val timeoutMs = (12_000L * round) + 2_000L
                    val measured = withTimeoutOrNull(timeoutMs) {
                        testUri(uris[index], testUrl, round, index)
                    } ?: Candidate(uris[index], -1, attempts = round, inputIndex = index, error = "measurement timed out")
                    results[index] = if (maxPingMs > 0 && measured.ms > maxPingMs) {
                        measured.copy(ms = -1, error = "latency exceeded ${maxPingMs}ms")
                    } else measured
                    val completed = done.incrementAndGet()
                    if (progressReporter.shouldEmit(completed, uris.size, SystemClock.elapsedRealtime())) {
                        onProgress?.invoke(completed, uris.size, round)
                    }
                }
            }
        }
        for (index in uris.indices) jobs.send(index)
        jobs.close()
        coroutineContext[kotlinx.coroutines.Job]?.children?.forEach { it.join() }
        rankCandidates(results.filterNotNull().filter { it.ms >= 0 }, keepTop)
    }

    internal fun rankCandidates(candidates: List<Candidate>, keepTop: Int): List<Candidate> =
        candidates.sortedWith(
            compareByDescending<Candidate> { if (it.attempts == 0) 0.0 else it.successes.toDouble() / it.attempts }
                .thenBy { it.ms }
                .thenBy { it.jitterMs }
                .thenBy { it.inputIndex }
        ).let { if (keepTop > 0) it.take(keepTop) else it }

    private fun testUri(uri: String, testUrl: String, attempts: Int, inputIndex: Int): Candidate {
        val outbound = try {
            UriParser.parseURIToOutbound(uri)
        } catch (exception: Exception) {
            return Candidate(uri, -1, attempts = attempts, inputIndex = inputIndex, error = "parse error: ${exception.message}")
        }
        if (uri.substringBefore("://").lowercase() !in udpSchemes) {
            val settings = outbound.optJSONObject("settings")
            val endpoint = settings?.optJSONArray("vnext")?.optJSONObject(0)
                ?: settings?.optJSONArray("servers")?.optJSONObject(0)
            val host = endpoint?.optString("address")
            val port = endpoint?.optInt("port", -1) ?: -1
            if (!host.isNullOrEmpty() && port > 0 && !tcpConnect(host, port, tcpPrecheckMs)) {
                return Candidate(uri, -1, attempts = attempts, inputIndex = inputIndex, error = "TCP pre-check failed")
            }
        }
        val configJson = """{"log":{"loglevel":"none"},"outbounds":[$outbound]}"""
        val samples = mutableListOf<Long>()
        repeat(attempts) {
            try {
                val value = libv2ray.Libv2ray.measureOutboundDelay(configJson, testUrl)
                if (value >= 0) samples += value
            } catch (_: Exception) {
                // A majority-success rule below turns repeated failures into a failed candidate.
            }
        }
        if (samples.size < attempts / 2 + 1) {
            return Candidate(uri, -1, successes = samples.size, attempts = attempts, inputIndex = inputIndex, error = "only ${samples.size}/$attempts attempts succeeded")
        }
        val ordered = samples.sorted()
        return Candidate(uri, ordered[ordered.size / 2], ordered.last() - ordered.first(), ordered.size, attempts, inputIndex)
    }

    private fun partial(
        candidates: List<Candidate>,
        round: Int,
        exception: Exception,
        onWarning: ((PipelineWarning) -> Unit)?
    ): List<Candidate> {
        val fallback = candidates.take(10)
        onWarning?.invoke(PipelineWarning("Round $round failed (${exception.message}); returning previous results", fallback))
        return fallback
    }

    private fun tcpConnect(host: String, port: Int, timeoutMs: Int): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs) }
        true
    } catch (_: Exception) {
        false
    }
}
