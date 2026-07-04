/// Shared event model for the proxy-testing pipeline, used by both the
/// Android (MethodChannel/EventChannel) and desktop (subprocess) backends.
///
/// `PipelineEvent.fromJson` deserializes the **flat** JSON-lines shape the
/// Go pipeline emits (see `go/main.go` / `go/pipeline.go`):
/// ```json
/// {"type":"status","message":"fetching subscription"}
/// {"type":"fetched","count":50}
/// {"type":"progress","round":1,"done":7,"total":50}
/// {"type":"result","rank":1,"ms":93,"uri":"ss://..."}
/// {"type":"done","count":10}
/// {"type":"error","message":"fetch failed: ..."}
/// ```
///
/// IMPORTANT: Android's existing `EventChannel` does NOT emit this shape.
/// It wraps everything as `{"type": ..., "data": ...}` (nested), has no
/// `result`/`done` stream events at all (those come back as the *return
/// value* of the `startPipeline` method call instead), and adds a
/// `warning` type Go doesn't have. `PipelineServiceAndroid` therefore
/// builds these event objects directly via their constructors rather than
/// calling `fromJson` — `fromJson` is only used by the desktop service,
/// where the wire format already matches this contract exactly.
sealed class PipelineEvent {
  const PipelineEvent();

  factory PipelineEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'status':
        return StatusEvent(json['message'] as String? ?? '');
      case 'fetched':
        return FetchedEvent(json['count'] as int? ?? 0);
      case 'progress':
        return ProgressEvent(
          round: json['round'] as int? ?? 0,
          done: json['done'] as int? ?? 0,
          total: json['total'] as int? ?? 0,
        );
      case 'result':
        return ResultEvent(
          rank: json['rank'] as int? ?? 0,
          ms: json['ms'] as int? ?? 0,
          uri: json['uri'] as String? ?? '',
        );
      case 'done':
        return DoneEvent(json['count'] as int? ?? 0);
      case 'warning':
        return WarningEvent(json['message'] as String? ?? '');
      case 'error':
        return ErrorEvent(json['message'] as String? ?? 'unknown error');
      default:
        return ErrorEvent('unrecognized event type: $type');
    }
  }
}

/// Free-text dev-facing status line (e.g. "fetching subscription", "stopped").
class StatusEvent extends PipelineEvent {
  final String message;
  const StatusEvent(this.message);
}

/// Subscription fetched and sampled; `count` is how many URIs entered round 1.
class FetchedEvent extends PipelineEvent {
  final int count;
  const FetchedEvent(this.count);
}

/// One worker finished testing one config within a round.
///
/// NOTE ON ORDERING: the Go pipeline currently emits these strictly
/// increasing per round (each worker increments `done` and emits while
/// holding the same mutex), so `done` should already arrive in order on
/// the wire. Consumers should still track `max(done)` seen per round
/// rather than trusting the latest value blindly — this is cheap
/// defense-in-depth against future pipeline changes (e.g. buffering,
/// reordering upstream) and costs nothing when events are already ordered.
class ProgressEvent extends PipelineEvent {
  final int round;
  final int done;
  final int total;
  const ProgressEvent({required this.round, required this.done, required this.total});
}

/// One ranked result. Rank is 1-based, sorted ascending by latency.
class ResultEvent extends PipelineEvent {
  final int rank;
  final int ms;
  final String uri;
  const ResultEvent({required this.rank, required this.ms, required this.uri});
}

/// Pipeline finished; `count` is the total number of results emitted.
class DoneEvent extends PipelineEvent {
  final int count;
  const DoneEvent(this.count);
}

/// Non-fatal warning (partial results, degraded run, etc). Android-only
/// today — the Go pipeline doesn't emit this type, but the UI should
/// handle it gracefully from either backend regardless.
class WarningEvent extends PipelineEvent {
  final String message;
  const WarningEvent(this.message);
}

/// Fatal error. Pipeline is expected to stop after this.
class ErrorEvent extends PipelineEvent {
  final String message;
  /// Optional machine-readable code, mirroring Android's PlatformException
  /// codes (EMPTY_BODY, DECODE_FAILURE, NO_VALID_SCHEMES, NETWORK_ERROR,
  /// PIPELINE_TIMEOUT) where available, so the UI can keep its existing
  /// per-error-type localized messages on both platforms.
  final String? code;
  const ErrorEvent(this.message, {this.code});
}
