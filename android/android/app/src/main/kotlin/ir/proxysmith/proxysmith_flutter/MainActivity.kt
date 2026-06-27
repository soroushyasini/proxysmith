package ir.proxysmith.proxysmith_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "ir.proxysmith/pipeline"
        const val EVENT_CHANNEL  = "ir.proxysmith/progress"
    }

    private var progressSink: EventChannel.EventSink? = null
    private var pipelineJob:  Job? = null

    // Single lifecycle-aware scope. SupervisorJob means a failed child
    // coroutine doesn't cancel the whole scope.
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Progress stream → Flutter ──────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    progressSink = sink
                }
                override fun onCancel(args: Any?) {
                    progressSink = null
                }
            })

        // ── Method calls from Flutter ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startPipeline" -> {
                        val subUrl    = call.argument<String>("subUrl")    ?: ""
                        val maxPingMs = call.argument<Int>("maxPingMs")?.toLong() ?: 8000L
                        val testUrl   = call.argument<String>("testUrl")
                            ?: "https://www.google.com/generate_204"

                        // TODO (UX pass): Flutter currently sends sampleN (legacy).
                        // Once the UI is updated to expose testCount, replace this
                        // mapping with: call.argument<Int>("testCount") ?: 200
                        //
                        // For now we accept both params and prefer testCount if present.
                        val testCount = call.argument<Int>("testCount")
                            ?: run {
                                // Legacy sampleN → convert to approximate testCount.
                                // sampleN=5 on a 8000-URI list ≈ 1600 tests, which
                                // is too many. Default to 200 when only sampleN given.
                                val sampleN = call.argument<Int>("sampleN") ?: 5
                                // A sampleN of 1 means "test all" → pass 0 (test all)
                                if (sampleN <= 1) 0 else 200
                            }

                        // Cancel any running pipeline before starting a new one
                        pipelineJob?.cancel()
                        pipelineJob = scope.launch {
                            runPipeline(subUrl, testCount, maxPingMs, testUrl, result)
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

    // Cancel all coroutines when the Activity is destroyed to avoid
    // background work outliving the Activity on real devices.
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
        result:    MethodChannel.Result
    ) {
        try {
            // 1. Fetch subscription and sample down to testCount URIs
            sendEvent("status", "fetching subscription...")
            val uris = SubscriptionFetcher.fetchAndSample(subUrl, testCount)
            sendEvent("fetched", uris.size)

            if (uris.isEmpty()) {
                withContext(Dispatchers.Main) {
                    result.error("NO_URIS", "No valid proxy URIs found in subscription.", null)
                }
                return
            }

            // 2. Run 3-round elimination pipeline with live progress events
            val top10 = Pipeline.run(
                uris       = uris,
                maxPingMs  = maxPingMs,
                testUrl    = testUrl,
                onProgress = { done, total, round ->
                    sendEvent("progress", mapOf(
                        "done"  to done,
                        "total" to total,
                        "round" to round
                    ))
                }
            )

            // 3. Return results to Flutter
            val resultList = top10.map { c ->
                mapOf("uri" to c.uri, "ms" to c.ms)
            }
            withContext(Dispatchers.Main) { result.success(resultList) }
            sendEvent("status", "done")

        } catch (e: CancellationException) {
            // User-initiated stop — not an error
            sendEvent("status", "stopped")
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Exception) {
            sendEvent("status", "error: ${e.message}")
            withContext(Dispatchers.Main) {
                result.error("PIPELINE_ERROR", e.message ?: "Unknown error", null)
            }
        }
    }

    // Sends a typed event to Flutter via the EventChannel.
    // Uses the shared scope (not a throwaway one) so these are tracked
    // and cancelled cleanly on destroy.
    private fun sendEvent(type: String, data: Any?) {
        scope.launch(Dispatchers.Main) {
            progressSink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
