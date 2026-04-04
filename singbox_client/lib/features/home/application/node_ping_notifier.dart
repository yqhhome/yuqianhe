import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/node_connectivity_test.dart';
import '../../../core/proxy/sspanel_singbox_config.dart';
import '../../../data/models/panel_node.dart';
import '../../../data/models/panel_user_stats.dart';

/// 客户端 TCP 建连测得的延迟（毫秒），按节点 id 缓存；Web 不测量。
class NodePingNotifier extends Notifier<Map<int, int?>> {
  static const int pending = -2;
  static const int failed = -1;

  @override
  Map<int, int?> build() => {};

  String? _lastMeasureSignature;

  /// 真实节点可用性测试：为每个节点生成 sing-box 配置并发起代理请求。
  Future<void> measureAll(List<PanelNode> nodes, PanelUserStats? stats) async {
    if (kIsWeb || nodes.isEmpty || stats == null) {
      return;
    }
    final next = Map<int, int?>.from(state);
    for (final n in nodes) {
      next[n.id] = pending;
    }
    state = Map<int, int?>.from(next);

    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= nodes.length) {
          return;
        }
        final current = nodes[index++];
        try {
          final cfg = buildSingboxConfigForPanelNode(
            node: current,
            stats: stats,
            includeTun: false,
          );
          if (!cfg.isOk || cfg.json == null) {
            next[current.id] = failed;
          } else {
            final ms = await measureNodeRealReachabilityMs(cfg.json!);
            next[current.id] = ms ?? failed;
          }
        } catch (_) {
          next[current.id] = failed;
        }
        state = Map<int, int?>.from(next);
      }
    }

    final concurrency = nodes.length < 6 ? nodes.length : 6;
    await Future.wait([
      for (var i = 0; i < concurrency; i++) worker(),
    ]);
  }

  /// 节点列表或用户端口变化时才重新测速，避免在 `build` 里重复排队。
  void scheduleIfNeeded(
    List<PanelNode> nodes,
    PanelUserStats? stats, {
    bool enabled = true,
  }) {
    if (kIsWeb || nodes.isEmpty || !enabled || stats == null) {
      return;
    }
    final sig = nodes
        .map((e) => '${e.id}:${e.rawServer ?? e.serverDisplay ?? ''}')
        .join('|');
    if (sig == _lastMeasureSignature) {
      return;
    }
    _lastMeasureSignature = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(measureAll(nodes, stats));
    });
  }

  void clear() {
    _lastMeasureSignature = null;
    state = {};
  }

  Future<void> refreshNow(List<PanelNode> nodes, PanelUserStats? stats) async {
    _lastMeasureSignature = null;
    state = {};
    await measureAll(nodes, stats);
  }
}

final nodePingProvider = NotifierProvider<NodePingNotifier, Map<int, int?>>(NodePingNotifier.new);

void scheduleNodePings(
  WidgetRef ref,
  List<PanelNode> nodes,
  PanelUserStats? stats, {
  bool enabled = true,
}) {
  ref.read(nodePingProvider.notifier).scheduleIfNeeded(
        nodes,
        stats,
        enabled: enabled,
      );
}
