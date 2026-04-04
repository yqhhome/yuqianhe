import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

bool get _isPhoneOrTablet {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// On Android/iOS, [127.0.0.1] / [localhost] point at the device, not the dev machine.
String? panelUrlLocalhostWarning(String? url) {
  if (!_isPhoneOrTablet || url == null || url.isEmpty) {
    return null;
  }
  final lower = url.toLowerCase().trim();
  if (lower.contains('127.0.0.1') || lower.contains('localhost')) {
    return '手机/平板上 127.0.0.1 与 localhost 指向本设备，无法访问电脑上的面板。'
        '请改为电脑的局域网地址，例如 http://192.168.0.10:8787（与电脑同一 Wi‑Fi）。';
  }
  return null;
}

/// Appended to generic connection errors on Android/iOS.
String panelUrlConnectionTroubleshootHint() {
  if (!_isPhoneOrTablet) {
    return '';
  }
  return ' 手机访问开发机时请使用电脑的局域网 IP（勿用 127.0.0.1），并与电脑处于同一网络。';
}
