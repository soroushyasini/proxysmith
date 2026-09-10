import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pipeline_event.dart';
import 'pipeline_service.dart';
import '../models/pipeline_options.dart';

/// Windows/Linux backend: spawns the standalone `proxysmith-pipeline-*`
/// Go binary as a subprocess and parses its `PSJSON:`-prefixed JSON-lines
/// stdout protocol.
class DesktopPipelineService implements PipelineService {
  Process? _process;

  String get _binaryName {
    if (Platform.isWindows) return 'proxysmith-pipeline-windows-amd64.exe';
    if (Platform.isLinux) return 'proxysmith-pipeline-linux-amd64';
    throw UnsupportedError(
      'No desktop pipeline binary for ${Platform.operatingSystem}.',
    );
  }

  /// Resolves the bundled binary using the documented bin/ convention:
  ///   Windows: build/windows/x64/runner/Release/bin/proxysmith-pipeline-windows-amd64.exe
  ///   Linux:   build/linux/x64/release/bundle/bin/proxysmith-pipeline-linux-amd64
  /// Keep this in sync with the build-time copy step that places the
  /// binary there — if one changes, the other must too.
  String get _binaryPath {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(exeDir, 'bin', _binaryName);
  }

  @override
  Stream<PipelineEvent> start(PipelineOptions options) {
    final controller = StreamController<PipelineEvent>();

    () async {
      if (options.validationError != null) {
        controller.add(
          const ErrorEvent(
            'Pipeline options are invalid.',
            code: 'INVALID_OPTIONS',
          ),
        );
        await controller.close();
        return;
      }
      if (_process != null) {
        controller.add(
          const ErrorEvent(
            'A pipeline run is already active.',
            code: 'ALREADY_RUNNING',
          ),
        );
        await controller.close();
        return;
      }
      final binaryPath = _binaryPath;
      if (!await File(binaryPath).exists()) {
        controller.add(
          ErrorEvent(
            'Pipeline binary not found at $binaryPath. It should be bundled '
            'next to the app under bin/ — see README desktop packaging.',
            code: 'BINARY_NOT_FOUND',
          ),
        );
        await controller.close();
        return;
      }

      try {
        final process = await Process.start(binaryPath, [
          '--sub-url-stdin',
          '--test-url-stdin',
          '--test-count',
          '${options.testCount}',
          '--max-ping-ms',
          '${options.maxPingMs}',
          '--concurrency',
          '${options.concurrency}',
          '--output-format',
          'jsonl',
        ]);
        _process = process;
        process.stdin.writeln(options.subUrl);
        process.stdin.writeln(options.testUrl);
        await process.stdin.close();
        var terminalEventSeen = false;

        // Drain stderr without surfacing it. It must still be read, or
        // a full pipe buffer can block the child process on some platforms.
        process.stderr.listen((_) {});

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (!line.startsWith('PSJSON:')) {
                  return; // Ignore dependency output; only parse our protocol.
                }
                try {
                  final json =
                      jsonDecode(line.substring(7)) as Map<String, dynamic>;
                  final event = PipelineEvent.fromJson(json);
                  terminalEventSeen =
                      terminalEventSeen ||
                      event is DoneEvent ||
                      event is ErrorEvent;
                  controller.add(event);
                } catch (_) {
                  // Malformed line — ignore rather than crash the stream.
                }
              },
              onDone: () async {
                final exitCode = await process.exitCode;
                // A non-zero, non-terminated-by-us exit with no prior 'error'
                // event means the process died before it could report why.
                if (exitCode != 0 &&
                    !terminalEventSeen &&
                    identical(_process, process)) {
                  controller.add(
                    ErrorEvent('pipeline process exited with code $exitCode'),
                  );
                }
                if (identical(_process, process)) _process = null;
                await controller.close();
              },
              onError: (error) {
                controller.add(ErrorEvent('stdout stream error: $error'));
              },
            );
      } on ProcessException catch (e) {
        _process?.kill();
        _process = null;
        controller.add(
          ErrorEvent('failed to start pipeline process: ${e.message}'),
        );
        await controller.close();
      } catch (e) {
        _process?.kill();
        _process = null;
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
    // Killing the child also tears down its in-flight Xray connections.
    process.kill();
  }
}
