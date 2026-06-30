import 'package:flutter/services.dart';

/// Method/event channel constants and a thin wrapper for talking to the
/// Kotlin side. Kept identical to v1.3.0's contract — MainActivity.kt
/// doesn't need to change for the UI redesign.
class PipelineBridge {
  static const methodChannel = MethodChannel('ir.proxysmith/pipeline');
  static const eventChannel = EventChannel('ir.proxysmith/progress');

  /// maxPingMs is no longer user-configurable in the UI (v2.0 change) —
  /// hardcoded here and sent to the backend unconditionally.
  static const int hardcodedMaxPingMs = 5000;

  static Future<dynamic> startPipeline({
    required String subUrl,
    required int testCount,
  }) {
    return methodChannel.invokeMethod('startPipeline', {
      'subUrl': subUrl,
      'testCount': testCount,
      'maxPingMs': hardcodedMaxPingMs,
    });
  }

  static Future<void> stopPipeline() {
    return methodChannel.invokeMethod('stopPipeline');
  }
}
