import 'dart:convert';

/// Builds sing-box JSON for development and tests.
/// Extend with parsers that turn panel `vless://` / `hysteria2://` into outbound maps.
class SingboxConfigBuilder {
  const SingboxConfigBuilder();

  /// Smallest valid-style config: local mixed inbound + outbounds (adjust for your sing-box version).
  /// [proxy] becomes tag `proxy`; keep `direct` for fallbacks in [route].
  String buildMinimal({
    required Map<String, dynamic> proxy,
    String logLevel = 'info',
    bool includeTun = false,
  }) {
    final proxyOutbound = Map<String, dynamic>.from(proxy)..['tag'] = 'proxy';

    final inbounds = <Map<String, dynamic>>[
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 2080,
      },
    ];

    if (includeTun) {
      inbounds.insert(0, {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.19.0.1/30'],
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
      });
    }

    final map = <String, dynamic>{
      'log': {'level': logLevel, 'timestamp': true},
      'inbounds': inbounds,
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
        proxyOutbound,
      ],
      'route': {
        'rules': [
          {'outbound': 'proxy'},
        ],
        'final': 'direct',
        'auto_detect_interface': true,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
