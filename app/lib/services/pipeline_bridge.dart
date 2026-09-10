import 'package:flutter/services.dart';
import '../models/pipeline_options.dart';

/// Method/event channel constants and the versioned options wrapper used to
/// communicate with the Kotlin pipeline.
class PipelineBridge {
  static const methodChannel = MethodChannel('ir.proxysmith/pipeline');
  static const eventChannel = EventChannel('ir.proxysmith/progress');

  static Future<dynamic> startPipeline(PipelineOptions options) {
    return methodChannel.invokeMethod('startPipeline', {
      'subUrl': options.subUrl,
      'testCount': options.testCount,
      'maxPingMs': options.maxPingMs,
      'concurrency': options.concurrency,
      'testUrl': options.testUrl,
    });
  }

  static Future<void> stopPipeline() {
    return methodChannel.invokeMethod('stopPipeline');
  }
}
