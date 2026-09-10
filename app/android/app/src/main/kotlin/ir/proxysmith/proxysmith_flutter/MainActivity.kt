package ir.proxysmith.proxysmith_flutter

import android.content.Intent
import android.os.Build
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "ir.proxysmith/pipeline"
        const val EVENT_CHANNEL  = "ir.proxysmith/progress"

        // Hard cap on the entire pipeline (fetch + all rounds).
        // If libv2ray hangs internally or the network stack freezes, the
        // pipeline would otherwise run forever — the user's only escape is
        // the STOP button, which requires the UI to remain responsive.
        // 10 minutes is generous: typical runs on 200-URI samples finish in
        // under 3 minutes. This is purely a safety net.
        private const val PIPELINE_HARD_TIMEOUT_MS = 10 * 60 * 1_000L  // 10 min
    }

    private var progressSink: EventChannel.EventSink? = null
    private var pipelineJob:  Job? = null

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    progressSink = sink
                }
                override fun onCancel(args: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startPipeline" -> {
                        val subUrl    = call.argument<String>("subUrl")    ?: ""
                        val maxPingMs = call.argument<Int>("maxPingMs")?.toLong() ?: 8000L
                        val testUrl   = call.argument<String>("testUrl")
                            ?: "https://cp.cloudflare.com/generate_204"

                        val concurrency = call.argument<Int>("concurrency") ?: 20

                        val testCount = call.argument<Int>("testCount")
                            ?: run {
                                val sampleN = call.argument<Int>("sampleN") ?: 5
                                if (sampleN <= 1) 0 else 200
                            }

                        if (!validHttpUrl(subUrl) || !validHttpUrl(testUrl) ||
                            testCount !in 1..5000 || maxPingMs !in 0L..60_000L || concurrency !in 1..60) {
                            result.error("INVALID_OPTIONS", "Pipeline options are outside the supported limits.", null)
                            return@setMethodCallHandler
                        }
                        if (pipelineJob?.isActive == true) {
                            result.error("ALREADY_RUNNING", "A pipeline run is already active.", null)
                            return@setMethodCallHandler
                        }
                        val serviceIntent = Intent(this, PipelineForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        pipelineJob = scope.launch {
                            runPipeline(subUrl, testCount, maxPingMs, testUrl, concurrency, result)
                        }
                    }

                    "stopPipeline" -> {
                        pipelineJob?.cancel()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    // ── Pipeline runner ────────────────────────────────────────────────────
    private suspend fun runPipeline(
        subUrl:    String,
        testCount: Int,
        maxPingMs: Long,
        testUrl:   String,
        concurrency: Int,
        result:    MethodChannel.Result
    ) {
        val startedAt = SystemClock.elapsedRealtime()
        try {
            withTimeout(PIPELINE_HARD_TIMEOUT_MS) {

                // 1. Fetch subscription
                sendEvent("status", "fetching subscription...")

                val fetchResult = SubscriptionFetcher.fetchAndSample(subUrl, testCount)

                val uris: List<String> = when (fetchResult) {
                    is FetchResult.Success -> fetchResult.uris

                    is FetchResult.EmptyBody -> {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "EMPTY_BODY",
                                "The subscription URL returned an empty response. " +
                                "Check the URL is correct and the server is up.",
                                null
                            )
                        }
                        return@withTimeout
                    }

                    is FetchResult.DecodeFailure -> {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "DECODE_FAILURE",
                                "The subscription content could not be decoded. " +
                                "It may be a login page, HTML error, or an unsupported encoding.",
                                null
                            )
                        }
                        return@withTimeout
                    }

                    is FetchResult.NoValidSchemes -> {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "NO_VALID_SCHEMES",
                                "The subscription was decoded but contains no supported proxy types. " +
                                "Supported: VMess, VLESS, Trojan, Shadowsocks, Hysteria2.",
                                null
                            )
                        }
                        return@withTimeout
                    }

                    is FetchResult.NetworkError -> {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "NETWORK_ERROR",
                                "Could not reach the subscription server after 3 attempts: " +
                                fetchResult.message,
                                null
                            )
                        }
                        return@withTimeout
                    }
                }

                sendEvent("fetched", uris.size)

                // 2. Run pipeline with partial-result warning callback
                val top10 = Pipeline.run(
                    uris       = uris,
                    concurrency = concurrency,
                    maxPingMs  = maxPingMs,
                    testUrl    = testUrl,
                    onProgress = { done, total, round ->
                        sendEvent("progress", mapOf(
                            "done"  to done,
                            "total" to total,
                            "round" to round
                        ))
                    },
                    onWarning  = { warning ->
                        sendEvent("warning", warning.message)
                    }
                )

                if (top10.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "NO_RESULTS",
                            "No configurations passed the latency and reliability checks.",
                            null
                        )
                    }
                    return@withTimeout
                }

                // 3. Return results
                val resultList = top10.map { c ->
                    mapOf(
                        "uri" to c.uri,
                        "ms" to c.ms,
                        "jitterMs" to c.jitterMs,
                        "successes" to c.successes,
                        "attempts" to c.attempts
                    )
                }
                withContext(Dispatchers.Main) { result.success(resultList) }
                sendEvent("done", mapOf(
                    "count" to resultList.size,
                    "elapsedMs" to SystemClock.elapsedRealtime() - startedAt
                ))
            }

        } catch (e: TimeoutCancellationException) {
            sendEvent("status", "pipeline timed out after ${PIPELINE_HARD_TIMEOUT_MS / 60_000} minutes")
            withContext(Dispatchers.Main) {
                result.error(
                    "PIPELINE_TIMEOUT",
                    "Pipeline exceeded the ${PIPELINE_HARD_TIMEOUT_MS / 60_000}-minute safety limit and was stopped.",
                    null
                )
            }
        } catch (e: CancellationException) {
            sendEvent("status", "stopped")
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Exception) {
            sendEvent("status", "error: ${e.message}")
            withContext(Dispatchers.Main) {
                result.error("PIPELINE_ERROR", e.message ?: "Unknown error", null)
            }
        } finally {
            stopService(Intent(this, PipelineForegroundService::class.java))
            pipelineJob = null
        }
    }

    private fun validHttpUrl(value: String): Boolean = try {
        val uri = java.net.URI(value)
        uri.host != null && uri.scheme?.lowercase() in setOf("http", "https")
    } catch (_: Exception) {
        false
    }

    private fun sendEvent(type: String, data: Any?) {
        scope.launch(Dispatchers.Main) {
            progressSink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
