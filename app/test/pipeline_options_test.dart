import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/models/pipeline_options.dart';

void main() {
  test('valid options cross the service boundary', () {
    const options = PipelineOptions(
      subUrl: 'https://example.com/sub?token=private',
      testCount: 350,
      maxPingMs: 5000,
      concurrency: 20,
      testUrl: 'https://cp.cloudflare.com/generate_204',
    );

    expect(options.validationError, isNull);
  });

  test('invalid URLs and numeric limits are rejected', () {
    const options = PipelineOptions(
      subUrl: 'file:///tmp/configs',
      testCount: 20,
      maxPingMs: -1,
      concurrency: 0,
      testUrl: 'not a url',
    );

    expect(options.validationError, isNotNull);
  });
}
