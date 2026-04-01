import 'package:shared_preferences/shared_preferences.dart';

/// Persisted panel origin, e.g. `https://example.com` (no trailing slash).
class PanelSettings {
  PanelSettings(this._prefs);

  static const _keyBaseUrl = 'panel_base_url';

  final SharedPreferences _prefs;

  String? get baseUrl {
    final v = _prefs.getString(_keyBaseUrl);
    if (v == null || v.trim().isEmpty) {
      return null;
    }
    return normalizeBaseUrl(v.trim());
  }

  Future<void> setBaseUrl(String url) async {
    final t = url.trim();
    if (t.isEmpty) {
      await _prefs.remove(_keyBaseUrl);
      return;
    }
    await _prefs.setString(_keyBaseUrl, normalizeBaseUrl(t));
  }

  /// Public for [AppServices.createDio].
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
