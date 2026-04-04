import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalBrowserLauncher {
  const ExternalBrowserLauncher._();

  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }

    if (kIsWeb) {
      return launchUrl(uri, mode: LaunchMode.platformDefault);
    }

    if (Platform.isAndroid) {
      final chromeUri = Uri.parse('googlechrome://navigate?url=${Uri.encodeComponent(uri.toString())}');
      if (await canLaunchUrl(chromeUri)) {
        final ok = await launchUrl(chromeUri, mode: LaunchMode.externalNonBrowserApplication);
        if (ok) {
          return true;
        }
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (Platform.isIOS) {
      final chromeScheme = uri.scheme == 'https' ? 'googlechromes' : 'googlechrome';
      final chromeUri = uri.replace(scheme: chromeScheme);
      if (await canLaunchUrl(chromeUri)) {
        final ok = await launchUrl(chromeUri, mode: LaunchMode.externalNonBrowserApplication);
        if (ok) {
          return true;
        }
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (Platform.isMacOS) {
      final chromeOk = await _runProcess(
        '/usr/bin/open',
        ['-a', 'Google Chrome', uri.toString()],
      );
      if (chromeOk) {
        return true;
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (Platform.isWindows) {
      final chromeExe = _findWindowsChrome();
      if (chromeExe != null) {
        final chromeOk = await _runProcess(chromeExe, [uri.toString()]);
        if (chromeOk) {
          return true;
        }
      }
      final edgeExe = _findWindowsEdge();
      if (edgeExe != null) {
        final edgeOk = await _runProcess(edgeExe, [uri.toString()]);
        if (edgeOk) {
          return true;
        }
      }
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> _runProcess(String executable, List<String> arguments) async {
    try {
      final process = await Process.start(executable, arguments, runInShell: false);
      unawaited(process.exitCode);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _findWindowsChrome() {
    final candidates = <String>[
      if (Platform.environment['ProgramFiles'] != null)
        '${Platform.environment['ProgramFiles']}\\Google\\Chrome\\Application\\chrome.exe',
      if (Platform.environment['ProgramFiles(x86)'] != null)
        '${Platform.environment['ProgramFiles(x86)']}\\Google\\Chrome\\Application\\chrome.exe',
      if (Platform.environment['LocalAppData'] != null)
        '${Platform.environment['LocalAppData']}\\Google\\Chrome\\Application\\chrome.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  static String? _findWindowsEdge() {
    final candidates = <String>[
      if (Platform.environment['ProgramFiles'] != null)
        '${Platform.environment['ProgramFiles']}\\Microsoft\\Edge\\Application\\msedge.exe',
      if (Platform.environment['ProgramFiles(x86)'] != null)
        '${Platform.environment['ProgramFiles(x86)']}\\Microsoft\\Edge\\Application\\msedge.exe',
      if (Platform.environment['LocalAppData'] != null)
        '${Platform.environment['LocalAppData']}\\Microsoft\\Edge\\Application\\msedge.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }
}
