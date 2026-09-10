class AppSettings {
  const AppSettings({
    this.darkMode = true,
    this.languageCode = 'en',
    this.selectedSourceId,
    this.testCount = 350,
    this.maxPingMs = 5000,
    this.concurrency = 20,
    this.testUrl = 'https://cp.cloudflare.com/generate_204',
  });

  static const defaults = AppSettings();

  factory AppSettings.sanitized({
    bool? darkMode,
    String? languageCode,
    String? selectedSourceId,
    int? testCount,
    int? maxPingMs,
    int? concurrency,
    String? testUrl,
  }) {
    final sourceId = selectedSourceId?.trim();
    return AppSettings(
      darkMode: darkMode ?? defaults.darkMode,
      languageCode: languageCode == 'en' || languageCode == 'fa'
          ? languageCode!
          : defaults.languageCode,
      selectedSourceId: sourceId == null || sourceId.isEmpty ? null : sourceId,
      testCount: testCount != null && testCount >= 1 && testCount <= 5000
          ? testCount
          : defaults.testCount,
      maxPingMs: maxPingMs != null && maxPingMs >= 0 && maxPingMs <= 60000
          ? maxPingMs
          : defaults.maxPingMs,
      concurrency: concurrency != null && concurrency >= 1 && concurrency <= 60
          ? concurrency
          : defaults.concurrency,
      testUrl: _isHttpUrl(testUrl) ? testUrl!.trim() : defaults.testUrl,
    );
  }

  final bool darkMode;
  final String languageCode;
  final String? selectedSourceId;
  final int testCount;
  final int maxPingMs;
  final int concurrency;
  final String testUrl;

  AppSettings copyWith({
    bool? darkMode,
    String? languageCode,
    String? selectedSourceId,
    int? testCount,
    int? maxPingMs,
    int? concurrency,
    String? testUrl,
  }) => AppSettings(
    darkMode: darkMode ?? this.darkMode,
    languageCode: languageCode ?? this.languageCode,
    selectedSourceId: selectedSourceId ?? this.selectedSourceId,
    testCount: testCount ?? this.testCount,
    maxPingMs: maxPingMs ?? this.maxPingMs,
    concurrency: concurrency ?? this.concurrency,
    testUrl: testUrl ?? this.testUrl,
  );

  static bool _isHttpUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }
}
