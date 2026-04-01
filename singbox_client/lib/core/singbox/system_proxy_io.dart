import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'singbox_constants.dart';

/// 将系统代理指向本机 sing-box mixed 入站。
Future<void> applySingboxGlobalHttpProxy({required bool enable}) async {
  if (Platform.isAndroid) {
    const channel = MethodChannel('yuqianhe/singbox_android');
    await channel.invokeMethod('setSystemProxy', {
      'enable': enable,
      'host': kSingboxMixedHost,
      'port': kSingboxMixedPort,
    });
    return;
  }
  if (Platform.isWindows) {
    await _applyWindowsSystemProxy(enable: enable);
    return;
  }
  if (!Platform.isMacOS) {
    return;
  }
  final services = await _allNetworkServices();
  if (services.isEmpty) {
    return;
  }

  for (final service in services) {
    try {
      if (!enable) {
        await Process.run('networksetup', ['-setwebproxystate', service, 'off']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'off']);
        continue;
      }
      final host = kSingboxMixedHost;
      final port = '$kSingboxMixedPort';
      await Process.run('networksetup', ['-setwebproxy', service, host, port]);
      await Process.run('networksetup', ['-setsecurewebproxy', service, host, port]);
      await Process.run('networksetup', ['-setwebproxystate', service, 'on']);
      await Process.run('networksetup', ['-setsecurewebproxystate', service, 'on']);
    } catch (_) {
      // 某些虚拟网卡或无权限服务可能失败，不应影响其它服务设置。
    }
  }
}

Future<void> _applyWindowsSystemProxy({required bool enable}) async {
  final host = kSingboxMixedHost;
  final port = '$kSingboxMixedPort';
  final proxyServer = '$host:$port';
  final script = '''
\$proxyKey = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings'
if (${enable ? '\$true' : '\$false'}) {
  Set-ItemProperty -Path \$proxyKey -Name ProxyServer -Value '$proxyServer'
  Set-ItemProperty -Path \$proxyKey -Name ProxyOverride -Value '<local>'
  Set-ItemProperty -Path \$proxyKey -Name ProxyEnable -Value 1
} else {
  Set-ItemProperty -Path \$proxyKey -Name ProxyEnable -Value 0
}
\$code = @"
using System;
using System.Runtime.InteropServices;
public static class WinInetProxyRefresh {
  [DllImport("wininet.dll", SetLastError=true)]
  public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
Add-Type -TypeDefinition \$code -ErrorAction SilentlyContinue | Out-Null
[WinInetProxyRefresh]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[WinInetProxyRefresh]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
''';
  for (final shell in const ['powershell', 'pwsh']) {
    try {
      final result = await Process.run(shell, [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      if (result.exitCode == 0) {
        return;
      }
    } catch (_) {
      // 尝试下一个 shell。
    }
  }
}

Future<String?> _primaryNetworkService() async {
  String? activeDevice;
  try {
    final r = await Process.run('route', ['-n', 'get', 'default']);
    if (r.exitCode == 0) {
      for (final line in const LineSplitter().convert(r.stdout.toString())) {
        final s = line.trim();
        if (s.startsWith('interface:')) {
          activeDevice = s.substring('interface:'.length).trim();
          break;
        }
      }
    }
  } catch (_) {}

  if (activeDevice != null && activeDevice.isNotEmpty) {
    final mapped = await _serviceNameByDevice(activeDevice);
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
  }

  final r = await Process.run('networksetup', ['-listallnetworkservices']);
  if (r.exitCode != 0) {
    return null;
  }
  final lines = const LineSplitter().convert(r.stdout.toString().trim());
  if (lines.length <= 1) {
    return null;
  }
  for (final line in lines.skip(1)) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('*')) {
      continue;
    }
    if (s.contains('Wi-Fi') || s.contains('Ethernet') || s.contains('以太网')) {
      return s;
    }
  }
  for (final line in lines.skip(1)) {
    final s = line.trim();
    if (s.isNotEmpty && !s.startsWith('*')) {
      return s;
    }
  }
  return null;
}

Future<List<String>> _allNetworkServices() async {
  final r = await Process.run('networksetup', ['-listallnetworkservices']);
  if (r.exitCode != 0) {
    return const <String>[];
  }
  final lines = const LineSplitter().convert(r.stdout.toString().trim());
  if (lines.length <= 1) {
    return const <String>[];
  }
  final out = <String>[];
  for (final line in lines.skip(1)) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('*')) {
      continue;
    }
    out.add(s);
  }

  // 将当前主服务放在前面，优先确保主网卡代理生效。
  final primary = await _primaryNetworkService();
  if (primary != null) {
    out.remove(primary);
    out.insert(0, primary);
  }
  return out;
}

Future<String?> _serviceNameByDevice(String device) async {
  final r = await Process.run('networksetup', ['-listnetworkserviceorder']);
  if (r.exitCode != 0) {
    return null;
  }
  final lines = const LineSplitter().convert(r.stdout.toString());
  String? currentService;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('(') && line.contains(')')) {
      final idx = line.indexOf(')');
      currentService = line.substring(idx + 1).trim();
      continue;
    }
    if (line.startsWith('(Hardware Port:') && currentService != null) {
      final m = RegExp(r'Device:\s*([^)]+)\)').firstMatch(line);
      final dev = m?.group(1)?.trim();
      if (dev == device) {
        return currentService;
      }
    }
  }
  return null;
}
