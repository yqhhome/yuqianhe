import 'package:shared_preferences/shared_preferences.dart';

import 'session_store_io.dart' if (dart.library.html) 'session_store_web.dart' as impl;

/// Persists last signed-in email for UI (session is in HTTP cookies).
///
/// Uses [AppServices.prefs] only. On **macOS**, email is stored in a small file under
/// the app support directory (no Keychain / no extra prefs writes), which avoids rare
/// sandbox/security plugin issues.
class SessionStore {
  SessionStore(this._prefs);

  final SharedPreferences _prefs;

  Future<void> saveEmail(String email) => impl.sessionStoreSaveEmail(_prefs, email);

  Future<String?> readEmail() => impl.sessionStoreReadEmail(_prefs);

  Future<void> clear() => impl.sessionStoreClear(_prefs);
}
