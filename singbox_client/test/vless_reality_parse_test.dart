import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/core/proxy/sspanel_singbox_config.dart';

void main() {
  test('parseVlessRealityServer maps public_key and short_id to pbk/sid fields', () {
    final m = parseVlessRealityServer(
      '{"add":"h.example.com","port":"443","public_key":"pk","short_id":"ab"}',
    );
    expect(m['pbk'], 'pk');
    expect(m['sid'], 'ab');
    expect(m['add'], 'h.example.com');
  });
}
