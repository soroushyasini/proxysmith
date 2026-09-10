import 'package:flutter_test/flutter_test.dart';
import 'package:proxysmith/models/config_source.dart';

void main() {
  test('stored custom sources reject malformed records independently', () {
    expect(
      ConfigSource.tryFromJson({
        'label': '',
        'url': 'file:///tmp/sub',
        'id': '',
      }),
      isNull,
    );
    expect(ConfigSource.tryFromJson('not a map'), isNull);
  });

  test('stored custom sources normalize valid records', () {
    final source = ConfigSource.tryFromJson({
      'label': '  Private source  ',
      'url': ' https://example.com/sub ',
      'id': ' source-1 ',
    });

    expect(source?.label, 'Private source');
    expect(source?.url, 'https://example.com/sub');
    expect(source?.id, 'source-1');
    expect(source?.isUserDefined, isTrue);
  });
}
