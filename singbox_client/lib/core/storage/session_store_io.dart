import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store_common.dart';

/// Non-web: macOS 使用应用支持目录下的明文文件存邮箱，避免 UserDefaults / 钥匙串相关异常；
/// 其它平台仍用 [SharedPreferences]。
Future<void> sessionStoreSaveEmail(SharedPreferences prefs, String email) async {
  final v = email.trim().toLowerCase();
  if (Platform.isMacOS) {
    final f = await _emailFile();
    await f.writeAsString(v, flush: true);
    return;
  }
  await prefs.setString(SessionStoreCommon.kEmail, v);
}

Future<String?> sessionStoreReadEmail(SharedPreferences prefs) async {
  if (Platform.isMacOS) {
    try {
      final f = await _emailFile();
      if (await f.exists()) {
        final t = (await f.readAsString()).trim();
        return t.isEmpty ? null : t;
      }
    } catch (_) {}
    // 旧版在 macOS 上曾写入 SharedPreferences，迁移到文件后删掉旧键
    final legacy = prefs.getString(SessionStoreCommon.kEmail);
    if (legacy != null && legacy.trim().isNotEmpty) {
      await sessionStoreSaveEmail(prefs, legacy);
      await prefs.remove(SessionStoreCommon.kEmail);
      return legacy.trim().toLowerCase();
    }
    return null;
  }
  return prefs.getString(SessionStoreCommon.kEmail);
}

Future<void> sessionStoreClear(SharedPreferences prefs) async {
  if (Platform.isMacOS) {
    try {
      final f = await _emailFile();
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    return;
  }
  await prefs.remove(SessionStoreCommon.kEmail);
}

Future<File> _emailFile() async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}/${SessionStoreCommon.fileName}');
}
