import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/app_services.dart';
import '../../../core/settings/panel_settings.dart';
import '../../../core/settings/panel_url_hints.dart';
import '../../../core/storage/session_store.dart';
import '../../../data/datasources/auth_remote_datasource.dart';
import '../../../data/models/login_request.dart';
import '../../../data/models/panel_api_response.dart';
import '../../../data/models/register_request.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_state.dart';

final appServicesProvider = Provider<AppServices>((ref) {
  throw UnimplementedError('Override appServicesProvider in main.dart');
});

final panelBaseUrlProvider = NotifierProvider<PanelBaseUrlNotifier, String?>(PanelBaseUrlNotifier.new);

class PanelBaseUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? url) {
    state = url == null || url.isEmpty ? null : PanelSettings.normalizeBaseUrl(url);
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(ref.read(appServicesProvider).prefs),
);

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final services = ref.watch(appServicesProvider);
  final url = ref.watch(panelBaseUrlProvider);
  return AuthRemoteDataSource(
    services,
    () {
      final u = url;
      if (u == null || u.isEmpty) {
        throw StateError('Panel base URL is not configured');
      }
      return u;
    },
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

class AuthNotifier extends Notifier<AuthViewState> {
  @override
  AuthViewState build() => const AuthViewState(status: AuthStatus.unknown);

  /// Loads saved panel URL and restores session when cookies are still valid.
  Future<void> bootstrapFromSettings() async {
    final services = ref.read(appServicesProvider);
    final saved = services.panelSettings.baseUrl;
    ref.read(panelBaseUrlProvider.notifier).set(saved);
    if (saved == null || saved.isEmpty) {
      state = const AuthViewState(status: AuthStatus.guest);
      return;
    }
    await refreshSession();
  }

  Future<void> setPanelBaseUrl(String url) async {
    final services = ref.read(appServicesProvider);
    await services.panelSettings.setBaseUrl(url);
    ref.read(panelBaseUrlProvider.notifier).set(url);
  }

  Future<void> refreshSession() async {
    final base = ref.read(panelBaseUrlProvider);
    if (base == null) {
      state = const AuthViewState(status: AuthStatus.guest);
      return;
    }
    final repo = ref.read(authRepositoryProvider);
    final email = await ref.read(sessionStoreProvider).readEmail();
    try {
      final ok = await repo.validateSession();
      if (ok) {
        state = AuthViewState(status: AuthStatus.authenticated, email: email);
      } else {
        state = const AuthViewState(status: AuthStatus.guest);
      }
    } catch (_) {
      state = AuthViewState(status: AuthStatus.guest, email: email, lastError: '无法验证登录状态');
    }
  }

  Future<void> login(LoginRequest request) async {
    state = state.copyWith(clearError: true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final res = await repo.login(request);
      if (res.success) {
        try {
          await ref.read(sessionStoreProvider).saveEmail(request.email);
        } catch (e, st) {
          // Do not block login if prefs write fails (e.g. rare macOS sandbox quirks).
          debugPrint('SessionStore.saveEmail failed: $e\n$st');
        }
        state = AuthViewState(status: AuthStatus.authenticated, email: request.email.trim().toLowerCase());
      } else {
        state = state.copyWith(status: AuthStatus.guest, lastError: res.message);
      }
    } catch (e, st) {
      debugPrint('login failed: $e\n$st');
      final msg = _formatLoginError(e);
      state = state.copyWith(status: AuthStatus.guest, lastError: msg);
    }
  }

  String _formatLoginError(Object e) {
    if (e is PlatformException) {
      final c = e.code;
      final m = e.message ?? '';
      if (c == '-34018' || m.contains('34018') || m.contains('entitlement')) {
        return '系统安全组件报错（$c）。若刚升级过客户端，请删除旧版应用后重装，或在项目目录执行 flutter clean 后重新打包。';
      }
      return '系统错误：$c ${m.isNotEmpty ? m : e.toString()}';
    }
    if (e is DioException) {
      final t = e.type;
      if (t == DioExceptionType.connectionTimeout || t == DioExceptionType.receiveTimeout) {
        return '连接超时，请检查网络与面板地址';
      }
      if (t == DioExceptionType.connectionError) {
        final base =
            '无法连接服务器：${e.message ?? "请检查网络、HTTPS 证书与防火墙"}';
        final hint = panelUrlConnectionTroubleshootHint();
        return hint.isEmpty ? base : '$base$hint';
      }
      if (t == DioExceptionType.badResponse) {
        return '服务器响应异常 (${e.response?.statusCode ?? "?"})';
      }
      return e.message ?? '网络错误';
    }
    return e.toString();
  }

  Future<PanelApiResponse> register(RegisterRequest request) async {
    state = state.copyWith(clearError: true);
    final repo = ref.read(authRepositoryProvider);
    final res = await repo.register(request);
    if (!res.success) {
      state = state.copyWith(lastError: res.message);
    }
    return res;
  }

  Future<PanelApiResponse> sendRegisterEmailCode(String email) async {
    final repo = ref.read(authRepositoryProvider);
    final res = await repo.sendEmailVerification(email);
    if (!res.success) {
      state = state.copyWith(lastError: res.message);
    }
    return res;
  }

  Future<void> logout() async {
    final base = ref.read(panelBaseUrlProvider);
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.logout();
    } catch (_) {
      // still clear local state
    }
    if (base != null && base.isNotEmpty) {
      await ref.read(appServicesProvider).clearCookiesForPanelBaseUrl(base);
    }
    await ref.read(sessionStoreProvider).clear();
    state = const AuthViewState(status: AuthStatus.guest);
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthViewState>(AuthNotifier.new);
