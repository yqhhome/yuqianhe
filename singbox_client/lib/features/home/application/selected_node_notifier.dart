import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/panel_node.dart';
import '../../auth/application/auth_notifier.dart';
import 'node_ping_notifier.dart';
import 'node_list_notifier.dart';

const _kSelectedNodeId = 'home_selected_node_id';

final selectedNodeIdProvider = NotifierProvider<SelectedNodeIdNotifier, int?>(SelectedNodeIdNotifier.new);

class SelectedNodeIdNotifier extends Notifier<int?> {
  final Random _random = Random();

  @override
  int? build() {
    return ref.read(appServicesProvider).prefs.getInt(_kSelectedNodeId);
  }

  Future<void> set(int? id) async {
    final p = ref.read(appServicesProvider).prefs;
    if (id == null) {
      await p.remove(_kSelectedNodeId);
    } else {
      await p.setInt(_kSelectedNodeId, id);
    }
    state = id;
  }

  /// 节点列表到达后：无选中时优先随机选择一个连通性正常的节点。
  Future<void> ensureDefault(List<PanelNode> nodes, {Map<int, int?>? pingMap}) async {
    if (nodes.isEmpty) {
      return;
    }
    final cur = state;
    final currentExists = cur != null && nodes.any((n) => n.id == cur);
    if (currentExists && (pingMap == null || pingMap.isEmpty)) {
      return;
    }
    if (pingMap == null || pingMap.isEmpty) {
      await set(nodes[_random.nextInt(nodes.length)].id);
      return;
    }
    final reachable = <PanelNode>[
      for (final node in nodes)
        if ((pingMap[node.id] ?? NodePingNotifier.pending) >= 0) node,
    ];
    if (reachable.isNotEmpty) {
      if (currentExists && reachable.any((node) => node.id == cur)) {
        return;
      }
      await set(reachable[_random.nextInt(reachable.length)].id);
      return;
    }
    final allMeasured = pingMap.length >= nodes.length;
    if (allMeasured) {
      await set(nodes[_random.nextInt(nodes.length)].id);
    }
  }
}

/// 当前选中的节点实体（若无则 `null`）。
final selectedPanelNodeProvider = Provider<PanelNode?>((ref) {
  final id = ref.watch(selectedNodeIdProvider);
  final nodes = ref.watch(nodeListProvider).valueOrNull;
  if (id == null || nodes == null || nodes.isEmpty) {
    return null;
  }
  for (final n in nodes) {
    if (n.id == id) {
      return n;
    }
  }
  return nodes.first;
});
