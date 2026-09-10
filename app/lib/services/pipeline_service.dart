import 'dart:io' show Platform;

import 'pipeline_event.dart';
import '../models/pipeline_options.dart';
import 'pipeline_service_android.dart';
import 'pipeline_service_desktop.dart';

/// Platform-agnostic interface for running the proxy-testing pipeline.
///
/// `pipeline_screen.dart` should depend only on this — never on
/// `PipelineBridge` or `Process` directly — so the same UI code drives
/// either backend.
abstract class PipelineService {
  /// Starts a pipeline run and returns a stream of events. The stream
  /// closes (without further events) once a [DoneEvent] or [ErrorEvent]
  /// has been delivered.
  Stream<PipelineEvent> start(PipelineOptions options);

  /// Stops the currently running pipeline, if any. Safe to call even if
  /// nothing is running.
  Future<void> stop();

  /// Returns the platform-appropriate implementation. Call once and reuse
  /// the instance for the lifetime of the screen/widget.
  static PipelineService create() {
    if (Platform.isAndroid) {
      return AndroidPipelineService();
    }
    if (Platform.isWindows || Platform.isLinux) {
      return DesktopPipelineService();
    }
    throw UnsupportedError(
      'ProxySmith pipeline is not supported on this platform '
      '(${Platform.operatingSystem}).',
    );
  }
}
