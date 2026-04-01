import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../singbox/singbox_constants.dart';

const MethodChannel _androidChannel = MethodChannel('yuqianhe/singbox_android');

Future<int?> measureNodeRealReachabilityMs(String configJson) async {
  if (Platform.isAndroid) {
    try {
      final ms = await _androidChannel
          .invokeMethod<int>('measureLatency', {
            'config': configJson,
          })
          .timeout(const Duration(seconds: 8));
      if (ms != null && ms > 0) {
        return ms;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  final bin = _resolveBinaryPath();
  if (bin == null) {
    return null;
  }

  final port = await _pickFreePort();
  if (port == null) {
    return null;
  }
  final effective = _overrideMixedInboundPort(configJson, port);

  final file = File(
    '${Directory.systemTemp.path}/singbox_node_test_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  Process? proc;
  HttpClient? client;
  try {
    await file.writeAsString(effective);
    proc = await Process.start(
      bin,
      ['run', '-c', file.path],
      mode: ProcessStartMode.normal,
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (await _exitedFast(proc)) {
      return null;
    }

    client = HttpClient();
    client.findProxy = (uri) => 'PROXY $kSingboxMixedHost:$port';
    client.connectionTimeout = const Duration(seconds: 5);
    final sw = Stopwatch()..start();
    final req = await client
        .getUrl(Uri.parse('https://www.google.com/generate_204'))
        .timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 8));
    await res.drain();
    sw.stop();
    if (res.statusCode == 204) {
      return sw.elapsedMilliseconds;
    }
  } catch (_) {
    // ignore
  } finally {
    client?.close(force: true);
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            proc?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {}
    }
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {}
  }
  return null;
}

Future<bool> _exitedFast(Process proc) async {
  try {
    final code = await proc.exitCode.timeout(
      const Duration(milliseconds: 120),
      onTimeout: () => -9999,
    );
    return code != -9999;
  } catch (_) {
    return false;
  }
}

Future<int?> _pickFreePort() async {
  ServerSocket? s;
  try {
    s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  } catch (_) {
    try {
      await s?.close();
    } catch (_) {}
    return null;
  }
}

String _overrideMixedInboundPort(String configJson, int port) {
  try {
    final root = jsonDecode(configJson);
    if (root is Map<String, dynamic>) {
      final inbounds = root['inbounds'];
      if (inbounds is List) {
        for (final item in inbounds) {
          if (item is Map<String, dynamic> && item['type'] == 'mixed') {
            item['listen'] = kSingboxMixedHost;
            item['listen_port'] = port;
          }
        }
      }
    }
    return const JsonEncoder.withIndent('  ').convert(root);
  } catch (_) {
    return configJson;
  }
}

String? _resolveBinaryPath() {
  final env = Platform.environment['SINGBOX_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  if (Platform.isWindows) {
    final candidates = <String>{};
    try {
      final exe = Platform.resolvedExecutable;
      final exeDir = File(exe).parent.path;
      candidates.add('$exeDir/sing-box.exe');
      candidates.add('$exeDir/data/sing-box.exe');
      candidates.add('$exeDir/../sing-box.exe');
    } catch (_) {}
    try {
      final cwd = Directory.current.path;
      candidates.add('$cwd/sing-box.exe');
      candidates.add('$cwd/data/sing-box.exe');
    } catch (_) {}
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          return file.resolveSymbolicLinksSync();
        } catch (_) {
          return file.path;
        }
      }
    }
    for (final command in const ['where.exe', 'where']) {
      try {
        final r = Process.runSync(command, ['sing-box.exe']);
        if (r.exitCode == 0) {
          final line = r.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first.trim();
          if (line.isNotEmpty && File(line).existsSync()) {
            return line;
          }
        }
      } catch (_) {}
      try {
        final r = Process.runSync(command, ['sing-box']);
        if (r.exitCode == 0) {
          final line = r.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first.trim();
          if (line.isNotEmpty && File(line).existsSync()) {
            return line;
          }
        }
      } catch (_) {}
    }
    return null;
  }
  try {
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;
    final bases = <String>[
      '$exeDir/../Resources',
      '$exeDir/../../Resources',
      '$exeDir/../../../Resources',
    ];
    for (final b in bases) {
      final p = File('$b/sing-box');
      if (p.existsSync()) {
        return p.resolveSymbolicLinksSync();
      }
    }
  } catch (_) {}
  for (final p in ['/opt/homebrew/bin/sing-box', '/usr/local/bin/sing-box']) {
    if (File(p).existsSync()) {
      return p;
    }
  }
  try {
    final r = Process.runSync('which', ['sing-box']);
    if (r.exitCode == 0) {
      final line = r.stdout.toString().trim().split('\n').first.trim();
      if (line.isNotEmpty && File(line).existsSync()) {
        return line;
      }
    }
  } catch (_) {}
  return null;
}

