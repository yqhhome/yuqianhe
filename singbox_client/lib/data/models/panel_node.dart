import 'package:equatable/equatable.dart';

/// One row from [VueController::getNodeList] `nodeinfo.nodes[]`.
/// [rawServer] 来自 `raw_node.server`（完整节点配置串），用于生成 sing-box。
class PanelNode extends Equatable {
  const PanelNode({
    required this.id,
    required this.name,
    required this.sort,
    this.serverDisplay,
    this.rawServer,
    this.pingMs,
    this.rawData = const {},
  });

  final int id;
  final String name;

  /// 面板节点类型：11/12=VMess，14=VLESS Reality，15=Hysteria2 等。
  final int sort;

  /// 列表里展示的 `server` 字段（可能被脱敏为 `***`）。
  final String? serverDisplay;

  /// 完整 `server` 字符串，通常仅在 `raw_node.server` 中存在。
  final String? rawServer;

  /// 毫秒延迟；面板标准接口通常不提供，部分定制主题可能带 `ping` / `latency`。
  final int? pingMs;

  /// 节点整行原始字段（来自 `nodeinfo.nodes[]`），用于兼容不同面板字段命名。
  final Map<String, dynamic> rawData;

  factory PanelNode.fromJson(Map<String, dynamic> json) {
    int? ping;
    final p = json['ping'] ?? json['latency'] ?? json['delay'];
    if (p is num) {
      ping = p.round();
    } else if (p is String) {
      ping = int.tryParse(p);
    }
    final sort = (json['sort'] as num?)?.toInt() ?? -1;
    String? raw;
    final rawNode = json['raw_node'];
    if (rawNode is Map) {
      final m = Map<String, dynamic>.from(rawNode);
      final s = m['server'];
      if (s != null && s.toString().trim().isNotEmpty) {
        raw = s.toString();
      }
    }
    return PanelNode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      sort: sort,
      serverDisplay: json['server']?.toString(),
      rawServer: raw,
      pingMs: ping,
      rawData: Map<String, dynamic>.from(json),
    );
  }

  /// 列表展示用：有数值则 `123 ms`，否则 `—`。
  String get pingDisplay => pingMs != null ? '$pingMs ms' : '—';

  /// TCP 测延迟用主机名（优先未脱敏的 `raw_node.server`，分号格式取首段）。
  String? get pingTargetHost {
    String? pick(String? s) {
      final t = s?.trim();
      if (t == null || t.isEmpty || t.contains('*')) {
        return null;
      }
      if (t.contains(';')) {
        return t.split(';').first.trim();
      }
      return t;
    }

    return pick(rawServer) ?? pick(serverDisplay);
  }

  @override
  List<Object?> get props => [id, name, sort, serverDisplay, rawServer, pingMs];
}
