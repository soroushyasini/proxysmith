import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/models/app_settings.dart';

void main() {
  test('saved settings are sanitized at the persistence boundary', () {
    final settings = AppSettings.sanitized(
      languageCode: 'unexpected',
      selectedSourceId: '   ',
      testCount: 9000,
      maxPingMs: -1,
      concurrency: 0,
      testUrl: 'file:///tmp/probe',
    );

    expect(settings.languageCode, AppSettings.defaults.languageCode);
    expect(settings.selectedSourceId, isNull);
    expect(settings.testCount, AppSettings.defaults.testCount);
    expect(settings.maxPingMs, AppSettings.defaults.maxPingMs);
    expect(settings.concurrency, AppSettings.defaults.concurrency);
    expect(settings.testUrl, AppSettings.defaults.testUrl);
  });

  test('valid custom test endpoints survive sanitization', () {
    final settings = AppSettings.sanitized(
      testUrl: 'https://example.com/health',
      concurrency: 60,
      maxPingMs: 0,
      testCount: 5000,
      languageCode: 'fa',
    );

    expect(settings.testUrl, 'https://example.com/health');
    expect(settings.concurrency, 60);
    expect(settings.maxPingMs, 0);
    expect(settings.testCount, 5000);
    expect(settings.languageCode, 'fa');
  });
}
