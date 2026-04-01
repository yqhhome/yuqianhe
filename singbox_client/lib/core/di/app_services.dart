import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/panel_settings.dart';

/// Application-wide services initialized in [initialize] before [runApp].
class AppServices {
  AppServices._(this._prefs, this._cookieJar);

  final SharedPreferences _prefs;
  final CookieJar _cookieJar;

  /// Same instance used by [PanelSettings] and [SessionStore] (single UserDefaults / prefs file).
  SharedPreferences get prefs => _prefs;

  PanelSettings get panelSettings => PanelSettings(_prefs);

  /// Clears persisted cookies for [baseUrl] (host + domain-scoped). Call before
  /// password login so [PersistCookieJar] does not send a stale session — otherwise
  /// the panel's Guest middleware returns 302→`/user` and never runs `loginHandle`.
  Future<void> clearCookiesForPanelBaseUrl(String baseUrl) async {
    final normalized = PanelSettings.normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      return;
    }
    try {
      final uri = Uri.parse(normalized);
      await _cookieJar.delete(uri, true);
    } catch (_) {
      // ignore parse/storage errors
    }
  }

  /// Creates a [Dio] bound to [baseUrl] with shared cookie persistence.
  Dio createDio(String baseUrl) {
    final normalized = PanelSettings.normalizeBaseUrl(baseUrl);
    final dio = Dio(
      BaseOptions(
        baseUrl: normalized,
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 25),
        // Form POST redirects are handled manually in [AuthRemoteDataSource] so POST is not turned into GET.
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        headers: <String, dynamic>{
          // Browser-like UA; avoid forcing `Accept: application/json` on all routes
          // (session check is GET HTML `/user`; auth POSTs set their own Accept).
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ),
    );
    dio.interceptors.add(CookieManager(_cookieJar));
    return dio;
  }

  static Future<AppServices> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final CookieJar jar;
    if (kIsWeb) {
      // No filesystem; in-memory only (cookies lost on full page reload).
      jar = CookieJar();
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final storage = FileStorage('${dir.path}/panel_cookie_jar');
      jar = PersistCookieJar(storage: storage);
    }
    return AppServices._(prefs, jar);
  }
}
