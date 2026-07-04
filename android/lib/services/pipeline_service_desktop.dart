import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pipeline_bridge.dart';
import 'pipeline_event.dart';
import 'pipeline_service.dart';

/// Windows/Linux backend: spawns the standalone `proxysmith-pipeline-*`
/// Go binary as a subprocess and parses its `PSJSON:`-prefixed JSON-lines
/// stdout protocol (see §3.1/§3.2 of the desktop port handoff doc).
class DesktopPipelineService implements PipelineService {
  Process? _process;

  String get _binaryName {
    if (Platform.isWindows) return 'proxysmith-pipeline-windows-amd64.exe';
    if (Platform.isLinux) return 'proxysmith-pipeline-linux-amd64';
    throw UnsupportedError(
      'No desktop pipeline binary for ${Platform.operatingSystem}.',
    );
  }

  /// Resolves the bundled binary relative to the running executable, per
  /// the bin/ subfolder convention set up in §7:
  ///   Windows: build/windows/x64/runner/Release/bin/proxysmith-pipeline-windows-amd64.exe
  ///   Linux:   build/linux/x64/release/bundle/bin/proxysmith-pipeline-linux-amd64
  /// Keep this in sync with the build-time copy step that places the
  /// binary there — if one changes, the other must too.
  String get _binaryPath {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(exeDir, 'bin', _binaryName);
  }

  @override
  Stream<PipelineEvent> start({required String subUrl, required int testCount}) {
    final controller = StreamController<PipelineEvent>();

    () async {
      final binaryPath = _binaryPath;
      if (!await File(binaryPath).exists()) {
        controller.add(ErrorEvent(
          'Pipeline binary not found at $binaryPath. It should be bundled '
          'next to the app under bin/ — see §7 of the desktop port handoff doc.',
          code: 'BINARY_NOT_FOUND',
        ));
        await controller.close();
        return;
      }

      try {
        final process = await Process.start(binaryPath, [
          '--sub-url', subUrl,
          '--test-count', '$testCount',
          // Kept in sync with Android's hardcoded value so both platforms
          // behave identically — maxPingMs isn't user-configurable in the
          // UI on either platform (see pipeline_bridge.dart).
          '--max-ping-ms', '${PipelineBridge.hardcodedMaxPingMs}',
          '--output-format', 'jsonl',
        ]);
        _process = process;

        // Drain stderr without surfacing it. We deliberately don't parse
        // it (per §5: "stderr is where xray-core's other logging may
        // still go; do not merge streams") but it must still be read, or
        // a full pipe buffer can block the child process on some platforms.
        process.stderr.listen((_) {});

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (!line.startsWith('PSJSON:')) return; // §3.2 — defense in depth
            try {
              final json = jsonDecode(line.substring(7)) as Map<String, dynamic>;
              controller.add(PipelineEvent.fromJson(json));
            } catch (_) {
              // Malformed line — ignore rather than crash the stream.
            }
          },
          onDone: () async {
            final exitCode = await process.exitCode;
            // A non-zero, non-terminated-by-us exit with no prior 'error'
            // event means the process died before it could report why.
            if (exitCode != 0 && _process != null) {
              controller.add(ErrorEvent('pipeline process exited with code $exitCode'));
            }
            _process = null;
            await controller.close();
          },
          onError: (error) {
            controller.add(ErrorEvent('stdout stream error: $error'));
          },
        );
      } on ProcessException catch (e) {
        controller.add(ErrorEvent('failed to start pipeline process: ${e.message}'));
        await controller.close();
      } catch (e) {
        controller.add(ErrorEvent('failed to start pipeline process: $e'));
        await controller.close();
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    // Hard kill, not graceful — acceptable since killing the OS process
    // also tears down any in-flight xray connections it owns; no explicit
    // cleanup is needed on the Go side (§5).
    process.kill(ProcessSignal.sigterm);
  }
}
