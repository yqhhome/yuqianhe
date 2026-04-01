import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/core/config/singbox_config_builder.dart';

void main() {
  test('buildMinimal returns valid JSON with proxy tag', () {
    const b = SingboxConfigBuilder();
    final json = b.buildMinimal(proxy: {'type': 'direct'});
    expect(json.contains('"tag": "proxy"'), isTrue);
    expect(json.contains('"type": "mixed"'), isTrue);
  });
}
