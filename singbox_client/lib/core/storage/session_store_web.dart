import 'package:shared_preferences/shared_preferences.dart';

import 'session_store_common.dart';

Future<void> sessionStoreSaveEmail(SharedPreferences prefs, String email) =>
    prefs.setString(SessionStoreCommon.kEmail, email.trim().toLowerCase());

Future<String?> sessionStoreReadEmail(SharedPreferences prefs) async =>
    prefs.getString(SessionStoreCommon.kEmail);

Future<void> sessionStoreClear(SharedPreferences prefs) =>
    prefs.remove(SessionStoreCommon.kEmail);
