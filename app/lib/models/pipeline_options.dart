class PipelineOptions {
  const PipelineOptions({
    required this.subUrl,
    required this.testCount,
    required this.maxPingMs,
    required this.concurrency,
    required this.testUrl,
  });

  final String subUrl;
  final int testCount;
  final int maxPingMs;
  final int concurrency;
  final String testUrl;

  String? get validationError {
    if (!_isHttpUrl(subUrl)) return 'invalid_subscription_url';
    if (!_isHttpUrl(testUrl)) return 'invalid_test_url';
    if (testCount < 1 || testCount > 5000) return 'invalid_test_count';
    if (maxPingMs < 0 || maxPingMs > 60000) return 'invalid_max_ping';
    if (concurrency < 1 || concurrency > 60) return 'invalid_concurrency';
    return null;
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }
}
