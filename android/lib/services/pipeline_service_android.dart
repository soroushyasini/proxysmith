import 'dart:async';

import 'package:flutter/services.dart';

import 'pipeline_bridge.dart';
import 'pipeline_event.dart';
import 'pipeline_service.dart';

/// Wraps the existing Kotlin `MethodChannel`/`EventChannel` bridge
/// (`pipeline_bridge.dart`, `MainActivity.kt`) and adapts it to the shared
/// [PipelineEvent] contract.
///
/// This is NOT a simple JSON reshape. Android's EventChannel differs from
/// the Go pipeline's JSON-lines contract in three ways, confirmed against
/// `MainActivity.kt`:
///
/// 1. Events arrive nested as `{"type": ..., "data": ...}` rather than flat.
/// 2. There are no `result` / `done` events on the stream at all — the
///    final ranked list comes back as the *return value* of the
///    `startPipeline` method call (a `Future`), which only resolves once
///    the whole pipeline finishes.
/// 3. Android emits a `warning` event type the Go pipeline doesn't have.
///
/// So this class merges two different sources — the EventChannel stream
/// (status/fetched/progress/warning, live during the run) and the
/// MethodChannel Future (the final result list, or a PlatformException) —
/// into one unified `Stream<PipelineEvent>` that behaves like the desktop
/// service's stream from the UI's point of view.
class AndroidPipelineService implements PipelineService {
  StreamSubscription? _eventSub;

  @override
  Stream<PipelineEvent> start({required String subUrl, required int testCount}) {
    final controller = StreamController<PipelineEvent>();

    _eventSub?.cancel();
    _eventSub = PipelineBridge.eventChannel.receiveBroadcastStream().listen(
      (event) {
        final e = Map<String, dynamic>.from(event as Map);
        final type = e['type'] as String;
        final data = e['data'];

        switch (type) {
          case 'status':
            controller.add(StatusEvent(data as String));
          case 'fetched':
            controller.add(FetchedEvent(data as int));
          case 'progress':
            final p = Map<String, dynamic>.from(data as Map);
            controller.add(ProgressEvent(
              round: p['round'] as int,
              done: p['done'] as int,
              total: p['total'] as int,
            ));
          case 'warning':
            controller.add(WarningEvent(data as String));
        }
      },
      onError: (error, stackTrace) {
        controller.add(ErrorEvent(error.toString()));
      },
    );

    () async {
      try {
        final raw = await PipelineBridge.startPipeline(
          subUrl: subUrl,
          testCount: testCount,
        );

        if (raw != null) {
          final list = (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          for (var i = 0; i < list.length; i++) {
            controller.add(ResultEvent(
              rank: i + 1,
              ms: list[i]['ms'] as int,
              uri: list[i]['uri'] as String,
            ));
          }
          controller.add(DoneEvent(list.length));
        }
        // raw == null means the pipeline was stopped (Kotlin's
        // CancellationException path resolves with result.success(null)) —
        // the 'status':'stopped' event already came through the stream,
        // so there's nothing further to emit here.
      } on PlatformException catch (e) {
        controller.add(ErrorEvent(e.message ?? e.code, code: e.code));
      } catch (e) {
        controller.add(ErrorEvent(e.toString()));
      } finally {
        await _eventSub?.cancel();
        await controller.close();
      }
    }();

    return controller.stream;
  }

  @override
  Future<void> stop() => PipelineBridge.stopPipeline();
}
