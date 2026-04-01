import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_paths.dart';
import '../../core/di/app_services.dart';
import '../models/login_request.dart';
import '../models/panel_api_response.dart';
import '../models/register_request.dart';

/// Low-level calls to SSPanel auth endpoints (form POST + JSON body).
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._services, this._baseUrlResolver);

  final AppServices _services;
  final String Function() _baseUrlResolver;

  Dio get _dio => _services.createDio(_baseUrlResolver());

  /// Matches browser jQuery.ajax: panel may return JSON only when these headers are set.
  Map<String, dynamic> _ajaxFormHeaders(String baseUrl, String refererPath) {
    final base = baseUrl.trim();
    final referer = Uri.parse(base).resolve(refererPath).toString();
    return <String, dynamic>{
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': referer,
      'Origin': Uri.parse(base).origin,
    };
  }

  String _stringFromResponseData(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) {
      try {
        return utf8.decode(data);
      } catch (_) {
        return '';
      }
    }
    if (data is Map) {
      return jsonEncode(data);
    }
    return data.toString();
  }

  /// POST form and follow 301/302/303/307/308 by **re-POSTing** to [Location].
  /// Dio’s automatic redirect often turns POST into GET on 302, which breaks SSPanel JSON APIs.
  /// [alreadyLoggedInJsonBody] — 仅用于注册/发信等：若服务器因「已登录」而 302→`/user`，可合成 JSON。
  /// **登录必须传 `null`**：否则会误把「未校验密码的 302」当成登录成功（严重安全问题）。
  Future<Response<dynamic>> _postForm(
    Dio dio,
    String path,
    Map<String, String> fields, {
    String? refererPath,
    String? alreadyLoggedInJsonBody,
  }) async {
    final ref = refererPath ?? path;
    final opts = Options(
      contentType: Headers.formUrlEncodedContentType,
      responseType: ResponseType.bytes,
      followRedirects: false,
      validateStatus: _allowThroughRedirects,
      headers: _ajaxFormHeaders(_baseUrlResolver(), ref),
    );

    var response = await dio.post<dynamic>(path, data: fields, options: opts);

    for (var hop = 0; hop < 10; hop++) {
      final code = response.statusCode ?? 0;
      if (!_isRedirectCode(code)) {
        break;
      }
      final loc = response.headers.value('location') ?? response.headers.value('Location');
      if (loc == null || loc.trim().isEmpty) {
        break;
      }
      if (_redirectMeansAlreadyLoggedIn(response.requestOptions.uri, loc)) {
        if (alreadyLoggedInJsonBody != null) {
          return _syntheticJsonResponse(response, alreadyLoggedInJsonBody);
        }
        // 登录流程：不得把 Guest 的「已登录」302 当成密码校验通过。
        return _syntheticJsonResponse(
          response,
          '{"ret":0,"msg":"会话仍显示已登录，无法校验密码。请稍后重试，或在网页端退出后再试。"}',
        );
      }
      final nextUri = _resolveRedirectUri(response.requestOptions.uri, loc.trim());
      response = await dio.postUri<dynamic>(nextUri, data: fields, options: opts);
    }
    return response;
  }

  static bool _allowThroughRedirects(int? status) =>
      status != null && status < 600;

  static bool _isRedirectCode(int code) =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  static Uri _resolveRedirectUri(Uri requestUri, String location) {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return Uri.parse(location);
    }
    return requestUri.resolve(location);
  }

  /// [Guest] 中间件：已登录用户访问 `/shouquan/*` 时会 **302 → `/user`**，且 **body 为空**。
  /// 若继续按「重定向 POST」去请求 `/user`，面板无对应 POST 路由，易得到 **HTTP 200 空正文**。
  static bool _redirectMeansAlreadyLoggedIn(Uri requestUri, String? locationHeader) {
    final loc = locationHeader?.trim();
    if (loc == null || loc.isEmpty) return false;
    final resolved = loc.startsWith('http://') || loc.startsWith('https://')
        ? Uri.parse(loc)
        : requestUri.resolve(loc);
    final p = resolved.path;
    return p == '/user' || p == '/user/' || p.startsWith('/user/');
  }

  Response<dynamic> _syntheticJsonResponse(
    Response<dynamic> from,
    String jsonUtf8,
  ) {
    return Response<dynamic>(
      data: jsonUtf8,
      statusCode: 200,
      requestOptions: from.requestOptions,
      headers: from.headers,
    );
  }

  /// 先 GET 登录/注册页，与浏览器一致建立 PHP 会话与 Cookie，再 POST。
  Future<void> _warmUpAuthGet(Dio dio, String getPath) async {
    try {
      await dio.get<dynamic>(
        getPath,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    } catch (_) {
      // 网络抖动时仍尝试 POST
    }
  }

  /// SSPanel returns JSON `{ret,msg}`; empty body / HTML / CDN pages must not crash [jsonDecode].
  PanelApiResponse _parsePanelResponse(Response<dynamic> response) {
    final code = response.statusCode;
    final data = response.data;

    if (data is Map<String, dynamic>) {
      return PanelApiResponse.fromJson(data);
    }
    if (data is Map) {
      return PanelApiResponse.fromJson(Map<String, dynamic>.from(data));
    }

    var raw = _stringFromResponseData(data).trim();
    if (raw.startsWith('\uFEFF')) {
      raw = raw.substring(1);
    }

    if (raw.isEmpty) {
      return PanelApiResponse(
        success: false,
        message:
            '服务器返回空内容（HTTP $code）。请确认「服务器地址」为网站根地址（与浏览器打开用户中心一致），例如 https://你的域名 ，不要带 /user 等路径。\n'
            '若浏览器中已登录同一账号，可先在网页退出登录，或在应用设置中清除 Cookie 后重试。',
      );
    }

    final lower = raw.toLowerCase();
    if (raw.startsWith('<') || lower.contains('<!doctype') || lower.contains('<html')) {
      return const PanelApiResponse(
        success: false,
        message:
            '返回了网页而不是登录接口数据。请把服务器地址改成网站根地址（仅域名与协议），并确认能打开用户中心。',
      );
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PanelApiResponse.fromJson(map);
    } catch (_) {
      final preview = raw.length > 100 ? '${raw.substring(0, 100)}…' : raw;
      return PanelApiResponse(
        success: false,
        message: '无法解析为 JSON（HTTP $code）。请检查面板地址与网络。\n$preview',
      );
    }
  }

  Future<PanelApiResponse> login(LoginRequest request) async {
    final base = _baseUrlResolver();
    // 必须先清本地 Cookie：仅请求服务端 logout 有时无法覆盖持久化 jar，仍会带上旧会话。
    await _services.clearCookiesForPanelBaseUrl(base);
    final dio = _services.createDio(base);
    // 再通知服务端作废会话（此时请求可能已不带 Cookie，仍无害）。
    try {
      await dio.get<dynamic>(
        ApiPaths.logout,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    } catch (_) {
      // 未登录时 logout 也可能失败，忽略
    }
    await _warmUpAuthGet(dio, ApiPaths.login);
    final response = await _postForm(
      dio,
      ApiPaths.login,
      request.toFormFields(),
      alreadyLoggedInJsonBody: null,
    );
    return _parsePanelResponse(response);
  }

  Future<PanelApiResponse> register(RegisterRequest request) async {
    final dio = _services.createDio(_baseUrlResolver());
    await _warmUpAuthGet(dio, ApiPaths.register);
    final response = await _postForm(
      dio,
      ApiPaths.register,
      request.toFormFields(),
      refererPath: ApiPaths.register,
      alreadyLoggedInJsonBody: '{"ret":1,"msg":"您已登录"}',
    );
    return _parsePanelResponse(response);
  }

  /// Ask server to send email verification code (when enabled in panel).
  Future<PanelApiResponse> sendEmailVerification(String email) async {
    final dio = _services.createDio(_baseUrlResolver());
    await _warmUpAuthGet(dio, ApiPaths.register);
    final response = await _postForm(
      dio,
      ApiPaths.sendEmailVerify,
      <String, String>{'email': email.trim().toLowerCase()},
      refererPath: ApiPaths.register,
      alreadyLoggedInJsonBody: '{"ret":1,"msg":"您已登录"}',
    );
    return _parsePanelResponse(response);
  }

  /// Clears server session; cookies are cleared via [AppServices] if needed.
  Future<void> logout() async {
    await _dio.get<dynamic>(ApiPaths.logout);
  }

  /// Returns true when GET [/user] returns 200 (session cookies accepted).
  Future<bool> validateSession() async {
    final response = await _dio.get<dynamic>(
      ApiPaths.userHome,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        headers: <String, dynamic>{
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
      ),
    );
    return response.statusCode == 200;
  }
}
