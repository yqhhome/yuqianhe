import 'dart:convert';
import 'dart:io';

import '../singbox/singbox_constants.dart';

class ProxyDiagnosticsResult {
  const ProxyDiagnosticsResult({
    required this.googleFinalUrl,
    required this.googleNcrFinalUrl,
    required this.publicIp,
    required this.country,
    required this.region,
    required this.city,
  });

  final String googleFinalUrl;
  final String googleNcrFinalUrl;
  final String? publicIp;
  final String? country;
  final String? region;
  final String? city;

  String toDisplayText() {
    final lines = <String>[
      'google.com => $googleFinalUrl',
      'google.com/ncr => $googleNcrFinalUrl',
      if (publicIp != null) '出口 IP => $publicIp',
      if (country != null || region != null || city != null)
        '地区 => ${[country, region, city].whereType<String>().where((e) => e.isNotEmpty).join(" / ")}',
    ];
    return lines.join('\n');
  }
}

Future<ProxyDiagnosticsResult> runProxyDiagnostics() async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY $kSingboxMixedHost:$kSingboxMixedPort';
  client.connectionTimeout = const Duration(seconds: 10);
  client.idleTimeout = const Duration(seconds: 15);

  try {
    final googleFinalUrl = await _fetchFinalUrl(
      client,
      Uri.parse('https://www.google.com/'),
    );
    final googleNcrFinalUrl = await _fetchFinalUrl(
      client,
      Uri.parse('https://www.google.com/ncr'),
    );
    final ipInfo = await _fetchIpInfo(client);
    return ProxyDiagnosticsResult(
      googleFinalUrl: googleFinalUrl,
      googleNcrFinalUrl: googleNcrFinalUrl,
      publicIp: ipInfo?['ip']?.toString(),
      country: ipInfo?['country']?.toString(),
      region: ipInfo?['region']?.toString(),
      city: ipInfo?['city']?.toString(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<String> _fetchFinalUrl(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri);
  final res = await req.close().timeout(const Duration(seconds: 12));
  await res.drain();
  if (res.redirects.isEmpty) {
    return uri.toString();
  }
  var current = uri;
  for (final redirect in res.redirects) {
    current = current.resolveUri(redirect.location);
  }
  return current.toString();
}

Future<Map<String, dynamic>?> _fetchIpInfo(HttpClient client) async {
  try {
    final req = await client.getUrl(Uri.parse('https://ipwho.is/'));
    final res = await req.close().timeout(const Duration(seconds: 12));
    final body = await utf8.decodeStream(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    // ignore diagnostics failure
  }
  return null;
}
