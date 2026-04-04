import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/panel_user_stats.dart';
import 'node_list_notifier.dart';

class UserStatsNotifier extends AsyncNotifier<PanelUserStats> {
  @override
  Future<PanelUserStats> build() async {
    return ref.read(userRemoteDataSourceProvider).fetchUserStats();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(userRemoteDataSourceProvider).fetchUserStats());
  }
}

final userStatsProvider = AsyncNotifierProvider<UserStatsNotifier, PanelUserStats>(UserStatsNotifier.new);
