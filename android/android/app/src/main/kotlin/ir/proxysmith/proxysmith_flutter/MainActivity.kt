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
    private var pipelineJob: Job? = null

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
                        val subUrl     = call.argument<String>("subUrl") ?: ""
                        val sampleN    = call.argument<Int>("sampleN") ?: 5
                        val maxPingMs  = call.argument<Int>("maxPingMs")?.toLong() ?: 8000L
                        val testUrl    = call.argument<String>("testUrl")
                            ?: "https://www.google.com/generate_204"

                        pipelineJob?.cancel()
                        pipelineJob = CoroutineScope(Dispatchers.IO).launch {
                            runPipeline(subUrl, sampleN, maxPingMs, testUrl, result)
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

    // ── Pipeline runner ────────────────────────────────────────────────────
    private suspend fun runPipeline(
        subUrl:    String,
        sampleN:   Int,
        maxPingMs: Long,
        testUrl:   String,
        result:    MethodChannel.Result
    ) {
        try {
            // 1. Fetch
            sendEvent("status", "fetching subscription...")
            val uris = SubscriptionFetcher.fetchAndSample(subUrl, sampleN)
            sendEvent("fetched", uris.size)

            // 2. Pipeline with progress
            val top10 = Pipeline.run(
                uris        = uris,
                concurrency = 20,
                maxPingMs   = maxPingMs,
                testUrl     = testUrl,
                onProgress  = { done, total, round ->
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
            withContext(Dispatchers.Main) {
                result.success(resultList)
            }
            sendEvent("status", "done")

        } catch (e: CancellationException) {
            sendEvent("status", "stopped")
            withContext(Dispatchers.Main) { result.success(null) }
        } catch (e: Exception) {
            sendEvent("status", "error: ${e.message}")
            withContext(Dispatchers.Main) { result.error("PIPELINE_ERROR", e.message, null) }
        }
    }

    private fun sendEvent(type: String, data: Any?) {
        CoroutineScope(Dispatchers.Main).launch {
            progressSink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
