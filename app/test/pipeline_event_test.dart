import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/services/pipeline_event.dart';

void main() {
  test('result event accepts additive quality metrics', () {
    final event = PipelineEvent.fromJson({
      'type': 'result',
      'rank': 1,
      'ms': 82,
      'jitterMs': 9,
      'successes': 3,
      'attempts': 3,
      'uri': 'vless://example',
    });

    expect(event, isA<ResultEvent>());
    final result = event as ResultEvent;
    expect(result.ms, 82);
    expect(result.jitterMs, 9);
    expect(result.successes, 3);
    expect(result.attempts, 3);
  });

  test('done event accepts elapsed duration while preserving old shape', () {
    final modern = PipelineEvent.fromJson({
      'type': 'done',
      'count': 10,
      'elapsedMs': 1234,
    });
    final legacy = PipelineEvent.fromJson({'type': 'done', 'count': 4});

    expect((modern as DoneEvent).elapsedMs, 1234);
    expect((legacy as DoneEvent).elapsedMs, isNull);
  });

  test('desktop error events preserve additive machine-readable codes', () {
    final event = PipelineEvent.fromJson({
      'type': 'error',
      'code': 'EMPTY_BODY',
      'message': 'subscription is empty',
    });

    expect((event as ErrorEvent).code, 'EMPTY_BODY');
  });
}
