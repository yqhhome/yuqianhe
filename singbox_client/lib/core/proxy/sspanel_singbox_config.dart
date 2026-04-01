import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/models/panel_node.dart';
import '../../data/models/panel_user_stats.dart';
import '../singbox/platform_info.dart';
import '../singbox/singbox_constants.dart';
import 'subscription_port.dart';

/// 与 PHP `Ramsey\Uuid::uuid3(NAMESPACE_DNS, '$id|$passwd')` 一致，用于 VLESS UUID。
String sspanelVlessUuid({required int userId, required String passwd}) {
  const nsHex = '6ba7b8109dad11d180b400c04fd430c8';
  final ns = <int>[];
  for (var i = 0; i < nsHex.length; i += 2) {
    ns.add(int.parse(nsHex.substring(i, i + 2), radix: 16));
  }
  final name = utf8.encode('$userId|$passwd');
  final input = <int>[...ns, ...name];
  final digest = md5.convert(input).bytes;
  final b = List<int>.from(digest);
  b[6] = (b[6] & 0x0f) | 0x30;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
}

/// 对齐 `Tools::vlessRealityArray`（分号分隔或 JSON）。
Map<String, String> parseVlessRealityServer(String node) {
  final trimmed = node.trim();
  if (trimmed.isEmpty) {
    return {};
  }
  try {
    final j = jsonDecode(trimmed);
    if (j is Map<String, dynamic>) {
      final m = j.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      final add = m['add'] ?? m['server'] ?? m['address'] ?? '';
      final pbk = m['pbk'] ?? m['public_key'] ?? '';
      final sid = m['sid'] ?? m['short_id'] ?? m['shortId'] ?? '';
      final sni = m['sni'] ?? m['server_name'] ?? '';
      final fp =
          m['fp'] ?? m['fingerprint'] ?? m['client_fingerprint'] ?? 'chrome';
      final type = m['type'] ?? m['net'] ?? m['network'] ?? 'tcp';
      return {
        'add': add,
        'port': m['port'] ?? '443',
        'pbk': pbk,
        'sid': sid,
        'sni': sni,
        'fp': fp.isEmpty ? 'chrome' : fp,
        'type': type.isEmpty ? 'tcp' : type,
        'flow': m['flow'] ?? '',
        'host': m['host'] ?? '',
        'path': m['path'] ?? '',
        'security': m['security'] ?? '',
        'encryption': m['encryption'] ?? '',
        'private_key': m['private_key'] ?? '',
        'dest': m['dest'] ?? '',
      };
    }
  } catch (_) {}
  final server = trimmed.split(';');
  final pbk2 = server.length > 2 ? server[2].trim() : '';
  final pk10 = server.length > 10 ? server[10].trim() : '';
  final pbk = pbk2.isNotEmpty ? pbk2 : pk10;
  return {
    'add': server.isNotEmpty ? server[0].trim() : '',
    'port':
        server.length > 1 && server[1].isNotEmpty ? server[1].trim() : '443',
    'pbk': pbk,
    'sid': server.length > 3 ? server[3].trim() : '',
    'sni': server.length > 4 ? server[4].trim() : '',
    'fp': server.length > 5 && server[5].trim().isNotEmpty
        ? server[5].trim()
        : 'chrome',
    'type': server.length > 6 && server[6].trim().isNotEmpty
        ? server[6].trim()
        : 'tcp',
    'flow': server.length > 7 ? server[7].trim() : '',
    'host': server.length > 8 ? server[8].trim() : '',
    'path': server.length > 9 ? server[9].trim() : '',
    'security': 'reality',
    'encryption': 'none',
    'private_key': pk10,
    'dest': server.length > 11 ? server[11].trim() : '',
  };
}

/// 对齐 `Tools::hysteria2Array`。
Map<String, String> parseHysteria2Server(String node) {
  final trimmed = node.trim();
  if (trimmed.isEmpty) {
    return {};
  }
  try {
    final j = jsonDecode(trimmed);
    if (j is Map<String, dynamic>) {
      final m = j.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      return {
        'server': m['server'] ?? '',
        'port': m['port'] ?? '443',
        'auth': m['auth'] ?? '',
        'sni': m['sni'] ?? '',
        'insecure': m['insecure'] ?? '0',
        'obfs': m['obfs'] ?? '',
        'obfs_password': m['obfs_password'] ?? '',
        'alpn': m['alpn'] ?? '',
      };
    }
  } catch (_) {}
  final server = trimmed.split(';');
  return {
    'server': server.isNotEmpty ? server[0] : '',
    'port': server.length > 1 && server[1].isNotEmpty ? server[1] : '443',
    'auth': server.length > 2 ? server[2] : '',
    'sni': server.length > 3 ? server[3] : '',
    'insecure': server.length > 4 ? server[4] : '0',
    'obfs': server.length > 5 ? server[5] : '',
    'obfs_password': server.length > 6 ? server[6] : '',
    'alpn': server.length > 7 ? server[7] : '',
  };
}

/// 对齐 [URL::parse_args]（`|` 分隔、`key=value`）。
Map<String, String> parseV2Args(String origin) {
  final out = <String, String>{};
  for (final arg in origin.split('|')) {
    final i = arg.indexOf('=');
    if (i <= 0 || i >= arg.length - 1) {
      continue;
    }
    out[arg.substring(0, i)] = arg.substring(i + 1);
  }
  return out;
}

/// 对齐 [Tools::v2Array]（VMess 节点 `raw_node.server` 分号串）。
Map<String, dynamic> parseV2Array(String node) {
  final server = node.trim().split(';');
  final item = <String, dynamic>{
    'host': '',
    'path': '',
    'tls': '',
  };
  if (server.isEmpty) {
    return item;
  }
  item['add'] = server[0];
  if (server.length >= 2) {
    final p = server[1];
    if (p == '0' || p.isEmpty) {
      item['port'] = 443;
    } else {
      item['port'] = int.tryParse(p) ?? 443;
    }
  } else {
    item['port'] = 443;
  }
  if (server.length >= 3) {
    item['aid'] = int.tryParse(server[2]) ?? 0;
  } else {
    item['aid'] = 0;
  }
  item['net'] = 'tcp';
  item['type'] = 'none';
  if (server.length >= 4) {
    item['net'] = server[3];
    if (item['net'] == 'ws') {
      item['path'] = '/';
    } else if (item['net'] == 'tls') {
      item['tls'] = 'tls';
    }
  }
  if (server.length >= 5) {
    final net = item['net'] as String;
    if (net == 'kcp' || net == 'http') {
      item['type'] = server[4];
    } else if (server[4] == 'ws') {
      item['net'] = 'ws';
    }
  }
  if (server.length >= 6) {
    final extra = parseV2Args(server[5]);
    for (final e in extra.entries) {
      item[e.key] = e.value;
    }
    if (item.containsKey('server')) {
      item['add'] = item['server'];
      item.remove('server');
    }
    if (item.containsKey('outside_port')) {
      item['port'] =
          int.tryParse(item['outside_port'].toString()) ?? item['port'];
      item.remove('outside_port');
    }
  }
  return item;
}

/// 解析节点测速目标，尽量与实际 sing-box 出站使用的地址/端口保持一致。
({String host, int port})? panelNodePingTarget({
  required PanelNode node,
  required int? userPort,
}) {
  final raw = node.rawServer?.trim();
  switch (node.sort) {
    case 0:
    case 10:
      final host =
          _legacySsHost(raw ?? '') ?? _legacySsHost(node.serverDisplay ?? '');
      if (host == null || host.isEmpty) {
        return null;
      }
      if (userPort == null) {
        return null;
      }
      return (
        host: host,
        port: subscriptionPortFromNodeName(node.name, userPort),
      );
    case 11:
    case 12:
      final source = raw ?? node.serverDisplay?.trim() ?? '';
      if (source.isEmpty) {
        return null;
      }
      final item = parseV2Array(source);
      final host = item['add']?.toString().trim() ?? '';
      if (host.isEmpty || host.contains('*')) {
        return null;
      }
      final basePort = switch (item['port']) {
        final int p => p,
        final num p => p.round(),
        final String s when s.isNotEmpty => int.tryParse(s) ?? 443,
        _ => 443,
      };
      return (
        host: host,
        port: subscriptionPortFromNodeName(node.name, basePort),
      );
    case 14:
      final item = parseVlessRealityServer(raw ?? node.serverDisplay ?? '');
      final host = (item['add'] ?? '').trim();
      if (host.isEmpty || host.contains('*')) {
        return null;
      }
      return (
        host: host,
        port: int.tryParse(item['port'] ?? '') ?? 443,
      );
    case 15:
      final item = parseHysteria2Server(raw ?? node.serverDisplay ?? '');
      final host = (item['server'] ?? '').trim();
      if (host.isEmpty || host.contains('*')) {
        return null;
      }
      return (
        host: host,
        port: int.tryParse(item['port'] ?? '') ?? 443,
      );
    default:
      final byRawMap = _genericPingTargetFromMap(node.rawData);
      return byRawMap ??
          _genericPingTarget(node.serverDisplay) ??
          _genericPingTarget(raw);
  }
}

({String host, int port})? _genericPingTargetFromMap(Map<String, dynamic> map) {
  if (map.isEmpty) {
    return null;
  }
  final rawNode = map['raw_node'];
  if (rawNode is Map) {
    final nested =
        _genericPingTargetFromMap(Map<String, dynamic>.from(rawNode));
    if (nested != null) {
      return nested;
    }
  }
  final host =
      (map['add'] ?? map['server'] ?? map['address'] ?? map['host'] ?? '')
          .toString()
          .trim();
  if (host.isEmpty || host.contains('*')) {
    return null;
  }
  final port = int.tryParse(
          (map['outside_port'] ?? map['server_port'] ?? map['port'] ?? '443')
              .toString()) ??
      443;
  return (host: host, port: port);
}

({String host, int port})? _genericPingTarget(String? source) {
  final trimmed = source?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.contains('*')) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final host =
          (map['add'] ?? map['server'] ?? map['host'] ?? '').toString().trim();
      if (host.isEmpty || host.contains('*')) {
        return null;
      }
      final port = int.tryParse(
              (map['outside_port'] ?? map['port'] ?? '443').toString()) ??
          443;
      return (host: host, port: port);
    }
  } catch (_) {}
  final parts = trimmed.split(';');
  final host = parts.first.trim();
  if (host.isEmpty || host.contains('*')) {
    return null;
  }
  final port = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 443) : 443;
  return (host: host, port: port);
}

class SingboxConfigResult {
  const SingboxConfigResult.ok(this.json) : errorMessage = null;
  const SingboxConfigResult.err(String msg)
      : json = null,
        errorMessage = msg;

  final String? json;
  final String? errorMessage;

  bool get isOk => json != null;
}

/// 根据面板节点 + 用户凭证生成 sing-box JSON（需 `raw_node.server` 完整字符串）。
SingboxConfigResult buildSingboxConfigForPanelNode({
  required PanelNode node,
  required PanelUserStats stats,
  required bool includeTun,
}) {
  final raw = node.rawServer;
  if (raw == null || raw.trim().isEmpty) {
    return const SingboxConfigResult.err(
        '节点缺少完整服务端配置（raw_node.server），请确认面板返回或升级面板。');
  }
  final passwd = stats.passwd;
  if (passwd == null || passwd.isEmpty) {
    return const SingboxConfigResult.err('无法读取用户密码字段，无法生成代理 UUID/密码。');
  }
  final uid = stats.userId;
  if (uid == null) {
    return const SingboxConfigResult.err('无法读取用户 ID。');
  }

  final vlessUuid = sspanelVlessUuid(userId: uid, passwd: passwd);

  switch (node.sort) {
    case 0:
    case 10:
      return _buildShadowsocksLegacy(
        raw: raw,
        nodeName: node.name,
        stats: stats,
        includeTun: includeTun,
      );
    case 11:
    case 12:
      return _buildVmess(
        raw: raw,
        nodeName: node.name,
        uuid: vlessUuid,
        includeTun: includeTun,
      );
    case 13:
      return const SingboxConfigResult.err(
        '当前节点类型 sort=13（SS-V2）尚未接入 sing-box，请使用 sort=0/10 或 VLESS Reality / Hysteria2 节点。',
      );
    case 14:
      return _buildVlessReality(
        raw: raw,
        uuid: vlessUuid,
        includeTun: includeTun,
      );
    case 15:
      return _buildHysteria2(
        raw: raw,
        passwd: passwd,
        includeTun: includeTun,
      );
    default:
      return SingboxConfigResult.err(
        '当前节点类型 sort=${node.sort} 尚未接入 sing-box 配置（已支持 0/10=Shadowsocks、11/12=VMess、14=VLESS Reality、15=Hysteria2）。',
      );
  }
}

/// 对齐 PHP [URL::getSSConnectInfo] 的简化版（用于 plain SS）。
({String protocol, String obfs}) _applySsConnectInfo(String? p, String? o) {
  var protocol = (p ?? 'origin').trim();
  var obfs = (o ?? 'plain').trim();
  if (_canObfsConnect(obfs) == 5) {
    obfs = 'plain';
  }
  if (_canProtocolConnect(protocol) == 3 && protocol != 'origin') {
    protocol = 'origin';
  }
  obfs = obfs.replaceAll('_compatible', '');
  protocol = protocol.replaceAll('_compatible', '');
  return (protocol: protocol, obfs: obfs);
}

int _canProtocolConnect(String protocol) {
  if (protocol == 'origin') {
    return 3;
  }
  if (!protocol.contains('_compatible')) {
    return 1;
  }
  return 3;
}

bool _isSsObfsBase(String obfsNoCompat) {
  const ss = {'http_simple', 'http_post'};
  return ss.contains(obfsNoCompat);
}

int _canObfsConnect(String obfs) {
  if (obfs == 'plain') {
    return 3;
  }
  final base = obfs.replaceAll('_compatible', '');
  if (_isSsObfsBase(base)) {
    if (!obfs.contains('_compatible')) {
      return 2;
    }
    return 4;
  }
  if (!obfs.contains('_compatible')) {
    return 1;
  }
  return 5;
}

String? _legacySsHost(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.contains('*')) {
    return null;
  }
  if (t.startsWith('{')) {
    return null;
  }
  if (t.contains(';')) {
    return t.split(';').first.trim();
  }
  return t;
}

/// 对齐 [URL::getV2Url] + sing-box [VMess](https://sing-box.sagernet.org/configuration/outbound/vmess/)。
SingboxConfigResult _buildVmess({
  required String raw,
  required String nodeName,
  required String uuid,
  required bool includeTun,
}) {
  final item = parseV2Array(raw);
  final host = item['add']?.toString().trim() ?? '';
  if (host.isEmpty || host.contains('*')) {
    return const SingboxConfigResult.err('VMess 解析失败：缺少有效地址。');
  }

  final basePort = switch (item['port']) {
    final int p => p,
    final num p => p.round(),
    final String s when s.isNotEmpty => int.tryParse(s) ?? 443,
    _ => 443,
  };
  final serverPort = subscriptionPortFromNodeName(nodeName, basePort);

  var net = (item['net'] ?? 'tcp').toString().toLowerCase();
  if (net == 'kcp' || net == 'http' || net == 'quic' || net == 'grpc') {
    return const SingboxConfigResult.err(
      'VMess 传输为 kcp/http/quic/grpc，当前未接入；请使用 TCP / WS / TLS 类节点。',
    );
  }

  final aid = switch (item['aid']) {
    final int v => v,
    final num v => v.round(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  final tlsFlag = item['tls']?.toString() == 'tls';
  final hostHeader = item['host']?.toString() ?? '';
  var path = item['path']?.toString() ?? '/';
  if (path.isEmpty) {
    path = '/';
  }

  final outbound = <String, dynamic>{
    'type': 'vmess',
    'tag': 'proxy',
    'server': host,
    'server_port': serverPort,
    'uuid': uuid,
    'security': 'auto',
    'alter_id': aid,
  };

  Map<String, dynamic> tlsOutbound({
    required String serverName,
  }) =>
      {
        'enabled': true,
        'server_name': serverName,
        'utls': {
          'enabled': true,
          'fingerprint': 'chrome',
        },
      };

  if (net == 'ws') {
    outbound['transport'] = {
      'type': 'ws',
      'path': path,
      if (hostHeader.isNotEmpty) 'headers': {'Host': hostHeader},
    };
    if (tlsFlag) {
      outbound['tls'] = tlsOutbound(
        serverName: hostHeader.isNotEmpty ? hostHeader : host,
      );
    }
  } else if (net == 'tls') {
    outbound['tls'] = tlsOutbound(
      serverName: hostHeader.isNotEmpty ? hostHeader : host,
    );
  } else if (tlsFlag) {
    outbound['tls'] = tlsOutbound(
      serverName: hostHeader.isNotEmpty ? hostHeader : host,
    );
  }

  return SingboxConfigResult.ok(_assembleJson(
    proxyOutbound: outbound,
    includeTun: includeTun,
  ));
}

SingboxConfigResult _buildShadowsocksLegacy({
  required String raw,
  required String nodeName,
  required PanelUserStats stats,
  required bool includeTun,
}) {
  final host = _legacySsHost(raw);
  if (host == null || host.isEmpty) {
    return const SingboxConfigResult.err('节点地址无效、为 JSON（SS-V2）或已被脱敏，无法连接。');
  }
  final userPort = stats.ssPort;
  if (userPort == null) {
    return const SingboxConfigResult.err('无法读取用户端口（port），无法连接 Shadowsocks 节点。');
  }
  final port = subscriptionPortFromNodeName(nodeName, userPort);
  final applied = _applySsConnectInfo(stats.ssProtocol, stats.ssObfs);
  if (applied.protocol != 'origin' || applied.obfs != 'plain') {
    return SingboxConfigResult.err(
      '当前账号需 SSR 或混淆（protocol=${applied.protocol}, obfs=${applied.obfs}），'
      '本客户端仅支持 origin + plain 的 Shadowsocks；请使用 VLESS Reality / Hysteria2 节点或在面板改为纯 SS。',
    );
  }
  final method = stats.ssMethod?.trim();
  if (method == null || method.isEmpty) {
    return const SingboxConfigResult.err('无法读取加密方式（method）。');
  }
  final passwd = stats.passwd;
  if (passwd == null || passwd.isEmpty) {
    return const SingboxConfigResult.err('无法读取用户密码。');
  }

  final outbound = <String, dynamic>{
    'type': 'shadowsocks',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'method': method,
    'password': passwd,
  };

  return SingboxConfigResult.ok(_assembleJson(
    proxyOutbound: outbound,
    includeTun: includeTun,
  ));
}

SingboxConfigResult _buildVlessReality({
  required String raw,
  required String uuid,
  required bool includeTun,
}) {
  final item = parseVlessRealityServer(raw);
  final host = (item['add'] ?? '').trim();
  final port = int.tryParse(item['port'] ?? '') ?? 443;
  final pbkRaw = (item['pbk'] ?? '').trim();
  final sid = (item['sid'] ?? '').trim();
  final sni = (item['sni'] ?? '').trim();
  final fp = (item['fp'] ?? 'chrome').trim();
  final flow = item['flow'] ?? '';
  final netType = (item['type'] ?? 'tcp').toLowerCase();
  final path = item['path'] ?? '';
  final wsHost = item['host'] ?? '';
  var security = (item['security'] ?? '').toLowerCase().trim();
  if (security.isEmpty) {
    security = 'reality';
  }

  if (host.isEmpty) {
    return const SingboxConfigResult.err('VLESS 解析失败：缺少地址。');
  }
  if (security == 'reality' && pbkRaw.isEmpty) {
    return const SingboxConfigResult.err(
        'VLESS Reality 解析失败：缺少公钥（pbk/public_key）。');
  }
  if (security == 'reality' &&
      sid.isNotEmpty &&
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(sid)) {
    return const SingboxConfigResult.err(
        'VLESS Reality 解析失败：short_id/sid 必须为十六进制。');
  }

  final serverName = sni.isNotEmpty ? sni : host;

  final outbound = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'uuid': uuid,
  };

  if (security != 'none') {
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': serverName,
      'utls': {
        'enabled': true,
        'fingerprint': fp.isEmpty ? 'chrome' : fp,
      },
    };
    if (security == 'reality') {
      final reality = <String, dynamic>{
        'enabled': true,
        'public_key': pbkRaw,
      };
      if (sid.isNotEmpty) {
        reality['short_id'] = sid;
      }
      tls['reality'] = reality;
    }
    outbound['tls'] = tls;
  }
  if (flow.isNotEmpty) {
    outbound['flow'] = flow;
  }
  if (netType == 'ws' && path.isNotEmpty) {
    outbound['transport'] = {
      'type': 'ws',
      'path': path,
      if (wsHost.isNotEmpty) 'headers': {'Host': wsHost},
    };
  }

  return SingboxConfigResult.ok(_assembleJson(
    proxyOutbound: outbound,
    includeTun: includeTun,
  ));
}

SingboxConfigResult _buildHysteria2({
  required String raw,
  required String passwd,
  required bool includeTun,
}) {
  final item = parseHysteria2Server(raw);
  final host = item['server'] ?? '';
  final port = int.tryParse(item['port'] ?? '') ?? 443;
  var auth = item['auth'] ?? '';
  if (auth.isEmpty) {
    auth = passwd;
  }
  final sni = item['sni'] ?? '';
  final insecure = item['insecure'] == '1' || item['insecure'] == 'true';

  if (host.isEmpty) {
    return const SingboxConfigResult.err('Hysteria2 解析失败：缺少服务器地址。');
  }

  final outbound = <String, dynamic>{
    'type': 'hysteria2',
    'tag': 'proxy',
    'server': host,
    'server_port': port,
    'password': auth,
    'tls': {
      'enabled': true,
      if (sni.isNotEmpty) 'server_name': sni,
      'insecure': insecure,
    },
  };

  final obfs = item['obfs'] ?? '';
  final obfsPw = item['obfs_password'] ?? '';
  if (obfs.isNotEmpty && obfsPw.isNotEmpty) {
    outbound['obfs'] = {
      'type': obfs,
      'password': obfsPw,
    };
  }

  return SingboxConfigResult.ok(_assembleJson(
    proxyOutbound: outbound,
    includeTun: includeTun,
  ));
}

String _assembleJson({
  required Map<String, dynamic> proxyOutbound,
  required bool includeTun,
}) {
  final inbounds = <Map<String, dynamic>>[
    {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': kSingboxMixedHost,
      'listen_port': kSingboxMixedPort,
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

  final route = <String, dynamic>{
    'final': 'proxy',
    'auto_detect_interface': includeTun && isAndroid ? true : !isAndroid,
    if (includeTun && isAndroid) 'override_android_vpn': true,
  };

  final proxyServerHost = proxyOutbound['server']?.toString().trim() ?? '';
  final androidTunDnsRules = <Map<String, dynamic>>[];
  if (includeTun && isAndroid) {
    if (_isDomainName(proxyServerHost)) {
      androidTunDnsRules.add({
        'server': 'local-dns',
        'domain': [proxyServerHost],
      });
    }
    androidTunDnsRules.add({
      'server': 'proxy-dns',
      'domain_suffix': [
        'google.com',
        'googleapis.com',
        'gstatic.com',
        'youtube.com',
        'youtu.be',
        'ytimg.com',
        'youtubei.googleapis.com',
        'facebook.com',
        'fbcdn.net',
        'instagram.com',
        'cdninstagram.com',
        'whatsapp.net',
      ],
    });
  }

  final dns = <String, dynamic>{
    'strategy': 'prefer_ipv4',
    'servers': [
      if (includeTun && isAndroid)
        {
          'type': 'https',
          'tag': 'proxy-dns',
          'server': '1.1.1.1',
          'server_port': 443,
          'path': '/dns-query',
          'tls': {
            'enabled': true,
            'server_name': 'cloudflare-dns.com',
          },
          'detour': 'proxy',
        },
      if (includeTun && isAndroid)
        {
          'type': 'https',
          'tag': 'proxy-dns-backup',
          'server': '8.8.8.8',
          'server_port': 443,
          'path': '/dns-query',
          'tls': {
            'enabled': true,
            'server_name': 'dns.google',
          },
          'detour': 'proxy',
        },
      {
        'type': 'local',
        'tag': 'local-dns',
      },
    ],
    if (androidTunDnsRules.isNotEmpty) 'rules': androidTunDnsRules,
    'final': includeTun && isAndroid ? 'proxy-dns' : 'local-dns',
  };

  final map = <String, dynamic>{
    'log': {'level': 'info', 'timestamp': true},
    'dns': dns,
    'inbounds': inbounds,
    'outbounds': [
      {'type': 'direct', 'tag': 'direct'},
      proxyOutbound,
    ],
    'route': route,
  };

  if (includeTun && isAndroid) {
    route['default_domain_resolver'] = 'proxy-dns';
  }

  return const JsonEncoder.withIndent('  ').convert(map);
}

bool _isDomainName(String host) {
  if (host.isEmpty) {
    return false;
  }
  if (host.contains(':')) {
    return false;
  }
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
    return false;
  }
  return host.contains('.');
}
