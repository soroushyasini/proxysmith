import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/widgets/options_menu.dart'
    show privacyPolicyUrl;

void main() {
  test('privacy policy URL points to the public repository policy', () {
    final uri = Uri.parse(privacyPolicyUrl);

    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(
      uri.path,
      '/soroushyasini/proxysmith/blob/main/docs/privacy-policy.md',
    );
  });
}
