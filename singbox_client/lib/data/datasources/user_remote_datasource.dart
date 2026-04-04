import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_paths.dart';
import '../../core/di/app_services.dart';
import '../models/panel_node.dart';
import '../models/panel_user_stats.dart';

class UserApiException implements Exception {
  UserApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Authenticated JSON APIs at panel root (same routes as Vue SPA).
class UserRemoteDataSource {
  UserRemoteDataSource(this._services, this._baseUrlResolver);

  final AppServices _services;
  final String Function() _baseUrlResolver;

  Map<String, dynamic> _jsonHeaders() {
    final base = _baseUrlResolver().trim();
    return <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': Uri.parse(base).resolve(ApiPaths.userHome).toString(),
      'Origin': Uri.parse(base).origin,
    };
  }

  Future<List<PanelNode>> fetchNodeList() async {
    final dio = _services.createDio(_baseUrlResolver());
    final res = await dio.get<dynamic>(
      ApiPaths.getNodeList,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        headers: _jsonHeaders(),
      ),
    );

    final code = res.statusCode ?? 0;
    if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
      throw UserApiException('登录已过期，请重新登录');
    }

    final data = res.data;
    List<int> bytes;
    if (data is List<int>) {
      bytes = data;
    } else if (data is String) {
      bytes = utf8.encode(data);
    } else {
      throw UserApiException('节点列表响应异常（HTTP $code）');
    }

    final raw = utf8.decode(bytes).trim();
    if (raw.isEmpty) {
      throw UserApiException('节点列表为空（HTTP $code）');
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw UserApiException('节点列表不是合法 JSON，请确认面板地址与登录状态');
    }

    final ret = map['ret'];
    if (ret == -1) {
      throw UserApiException('未登录或会话失效，请重新登录');
    }
    if (ret != 1) {
      throw UserApiException('面板返回异常 ret=$ret');
    }

    final nodeinfo = map['nodeinfo'];
    if (nodeinfo is! Map<String, dynamic>) {
      return const [];
    }
    final nodes = nodeinfo['nodes'];
    if (nodes is! List<dynamic>) {
      return const [];
    }

    final out = <PanelNode>[];
    for (final e in nodes) {
      if (e is Map<String, dynamic>) {
        out.add(PanelNode.fromJson(e));
      } else if (e is Map) {
        out.add(PanelNode.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Future<PanelUserStats> fetchUserStats() async {
    final dio = _services.createDio(_baseUrlResolver());
    final res = await dio.get<dynamic>(
      ApiPaths.getUserInfo,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        headers: _jsonHeaders(),
      ),
    );

    final code = res.statusCode ?? 0;
    if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
      throw UserApiException('登录已过期，请重新登录');
    }

    final data = res.data;
    List<int> bytes;
    if (data is List<int>) {
      bytes = data;
    } else if (data is String) {
      bytes = utf8.encode(data);
    } else {
      throw UserApiException('用户信息响应异常（HTTP $code）');
    }

    final raw = utf8.decode(bytes).trim();
    if (raw.isEmpty) {
      throw UserApiException('用户信息为空（HTTP $code）');
    }

    Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw UserApiException('用户信息不是合法 JSON');
    }

    final ret = map['ret'];
    if (ret == -1) {
      throw UserApiException('未登录或会话失效，请重新登录');
    }
    if (ret != 1) {
      throw UserApiException('面板返回异常 ret=$ret');
    }

    final info = map['info'];
    if (info is! Map) {
      throw UserApiException('缺少 info 字段');
    }
    final infoMap = Map<String, dynamic>.from(info);
    final user = infoMap['user'];
    if (user is! Map) {
      throw UserApiException('缺少 user 字段');
    }
    Map<String, dynamic>? annMap;
    final ann = infoMap['ann'];
    if (ann is Map) {
      annMap = Map<String, dynamic>.from(ann);
    }
    return PanelUserStats.fromApiMaps(
      user: Map<String, dynamic>.from(user),
      ann: annMap,
    );
  }
}
