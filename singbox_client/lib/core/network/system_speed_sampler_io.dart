import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

Future<(int, int)?> readMacNetworkBytes() async {
  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('yuqianhe/singbox_android');
      final map = await channel.invokeMapMethod<String, dynamic>('readTrafficStats');
      final rx = (map?['rx'] as num?)?.toInt();
      final tx = (map?['tx'] as num?)?.toInt();
      if (rx != null && tx != null && rx >= 0 && tx >= 0) {
        return (rx, tx);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
  if (Platform.isWindows) {
    return _readWindowsNetworkBytes();
  }
  if (!Platform.isMacOS) {
    return null;
  }
  try {
    final defaultIface = await _defaultRouteInterface();
    final r = await Process.run('netstat', const ['-ibn']);
    if (r.exitCode != 0) {
      return null;
    }
    final lines = r.stdout.toString().split('\n');
    var ibIdx = -1;
    var obIdx = -1;
    final byIface = <String, (int, int)>{};
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        continue;
      }
      if (ibIdx < 0 || obIdx < 0) {
        final head = t.split(RegExp(r'\s+'));
        final i = head.indexOf('Ibytes');
        final o = head.indexOf('Obytes');
        if (i >= 0 && o >= 0) {
          ibIdx = i;
          obIdx = o;
        }
        continue;
      }
      final cols = t.split(RegExp(r'\s+'));
      if (cols.isEmpty) {
        continue;
      }
      final name = cols.first;
      if (name == 'Name' || name == 'lo0') {
        continue;
      }
      if (ibIdx >= cols.length || obIdx >= cols.length) {
        continue;
      }
      final ib = int.tryParse(cols[ibIdx]);
      final ob = int.tryParse(cols[obIdx]);
      if (ib == null || ob == null) {
        continue;
      }
      // netstat 会给同一网卡多行（IPv4/IPv6 等），这里取该网卡的最大计数。
      final prev = byIface[name];
      if (prev == null) {
        byIface[name] = (ib, ob);
      } else {
        byIface[name] = (
          ib > prev.$1 ? ib : prev.$1,
          ob > prev.$2 ? ob : prev.$2,
        );
      }
    }
    if (byIface.isEmpty) {
      return null;
    }
    if (defaultIface != null) {
      final active = byIface[defaultIface];
      if (active != null) {
        return active;
      }
    }
    // 兜底：取累计字节最多的接口，避免误选到 awdl/bridge 这类低流量网卡。
    var best = byIface.values.first;
    for (final e in byIface.values.skip(1)) {
      if (e.$1 + e.$2 > best.$1 + best.$2) {
        best = e;
      }
    }
    return best;
  } catch (_) {}
  return null;
}

Future<(int, int)?> _readWindowsNetworkBytes() async {
  try {
    const script = r'''
$stats = Get-NetAdapterStatistics | Where-Object { $_.Name -notmatch '^Loopback|isatap|Teredo' } |
  Select-Object ReceivedBytes, SentBytes
if ($stats) {
  $rx = ($stats | Measure-Object -Property ReceivedBytes -Sum).Sum
  $tx = ($stats | Measure-Object -Property SentBytes -Sum).Sum
  @{ rx = $rx; tx = $tx } | ConvertTo-Json -Compress
}
''';
    for (final shell in const ['powershell', 'pwsh']) {
      try {
        final r = await Process.run(shell, const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ]);
        if (r.exitCode != 0) {
          continue;
        }
        final text = r.stdout.toString().trim();
        if (text.isEmpty) {
          continue;
        }
        final data = jsonDecode(text);
        if (data is Map) {
          final rx = (data['rx'] as num?)?.toInt();
          final tx = (data['tx'] as num?)?.toInt();
          if (rx != null && tx != null && rx >= 0 && tx >= 0) {
            return (rx, tx);
          }
        }
      } catch (_) {
        // try next shell
      }
    }
    final fallback = await Process.run('netstat', const ['-e']);
    if (fallback.exitCode == 0) {
      for (final raw in fallback.stdout.toString().split(RegExp(r'[\r\n]+'))) {
        final matches = RegExp(r'(\d+)').allMatches(raw).toList();
        if (matches.length < 2) {
          continue;
        }
        final rx = int.tryParse(matches[matches.length - 2].group(1)!);
        final tx = int.tryParse(matches[matches.length - 1].group(1)!);
        if (rx != null && tx != null && rx >= 0 && tx >= 0) {
          return (rx, tx);
        }
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<String?> _defaultRouteInterface() async {
  try {
    final r = await Process.run('route', const ['-n', 'get', 'default']);
    if (r.exitCode != 0) {
      return null;
    }
    final lines = r.stdout.toString().split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('interface:')) {
        final iface = t.substring('interface:'.length).trim();
        if (iface.isNotEmpty) {
          return iface;
        }
      }
    }
  } catch (_) {}
  return null;
}
