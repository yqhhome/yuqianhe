import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/panel_node.dart';
import '../../auth/application/auth_notifier.dart';
import 'node_list_notifier.dart';

const _kSelectedNodeId = 'home_selected_node_id';

final selectedNodeIdProvider = NotifierProvider<SelectedNodeIdNotifier, int?>(SelectedNodeIdNotifier.new);

class SelectedNodeIdNotifier extends Notifier<int?> {
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

  /// 节点列表到达后：无选中时默认第一个。
  Future<void> ensureDefault(List<PanelNode> nodes) async {
    if (nodes.isEmpty) {
      return;
    }
    final cur = state;
    if (cur != null && nodes.any((n) => n.id == cur)) {
      return;
    }
    await set(nodes.first.id);
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
