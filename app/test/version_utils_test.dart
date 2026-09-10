import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/utils/version_utils.dart';

void main() {
  test('compares semantic versions instead of string inequality', () {
    expect(isNewerVersion('2.4.0', '2.3.9'), isTrue);
    expect(isNewerVersion('2.3.0', '2.3.0'), isFalse);
    expect(isNewerVersion('2.2.9', '2.3.0'), isFalse);
    expect(isNewerVersion('v3.0.0-beta.1', '2.9.9'), isTrue);
  });
}
