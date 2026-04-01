import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/user_remote_datasource.dart';
import '../../../data/models/panel_node.dart';
import '../../auth/application/auth_notifier.dart';

final userRemoteDataSourceProvider = Provider<UserRemoteDataSource>((ref) {
  final services = ref.watch(appServicesProvider);
  final url = ref.watch(panelBaseUrlProvider);
  return UserRemoteDataSource(
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

class NodeListNotifier extends AsyncNotifier<List<PanelNode>> {
  @override
  Future<List<PanelNode>> build() async {
    final ds = ref.read(userRemoteDataSourceProvider);
    return ds.fetchNodeList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(userRemoteDataSourceProvider).fetchNodeList());
  }
}

final nodeListProvider = AsyncNotifierProvider<NodeListNotifier, List<PanelNode>>(NodeListNotifier.new);
