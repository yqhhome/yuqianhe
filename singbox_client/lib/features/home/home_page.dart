import 'dart:async' show Future, Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_version.dart';
import '../../core/proxy/sspanel_singbox_config.dart';
import '../../core/network/system_speed_sampler.dart';
import '../../core/singbox/platform_info.dart';
import '../../core/singbox/singbox_state.dart';
import '../../core/singbox/system_proxy.dart';
import '../../core/singbox/tun_inbound_support.dart';
import '../../core/util/country_flag.dart';
import '../../data/datasources/user_remote_datasource.dart';
import '../../data/models/panel_user_stats.dart';
import '../auth/application/auth_notifier.dart';
import 'application/client_ui_prefs_notifier.dart';
import 'ui/announcement_marquee.dart';
import 'application/node_list_notifier.dart';
import 'application/node_ping_notifier.dart';
import 'application/selected_node_notifier.dart';
import 'application/singbox_providers.dart';
import 'application/user_stats_notifier.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.userEmail});

  final String? userEmail;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const Duration _userStatsCacheTtl = Duration(minutes: 60);
  static const Duration _connectedStatsRefreshInterval = Duration(minutes: 60);
  static const Duration _powerActionMinLockDuration = Duration(milliseconds: 1200);

  Timer? _connTimer;
  Timer? _androidDiagnoseTimer;
  Timer? _accountStatusTimer;
  bool _androidDiagnoseShown = false;
  bool _accessBlockedDialogOpen = false;
  bool _powerActionLocked = false;
  DateTime? _lastUserStatsRefreshAt;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  DateTime? _lastSpeedSampleAt;
  int? _lastRxBytes;
  int? _lastTxBytes;
  double _downBytesPerSec = 0;
  double _upBytesPerSec = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _connTimer?.cancel();
    _androidDiagnoseTimer?.cancel();
    _accountStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowAndroidDiagnose(SingboxRunPhase phase) async {
    if (!mounted || !isAndroid) return;
    final tunMode = ref.read(clientUiPrefsProvider).tunMode;
    if (!tunMode) {
      _androidDiagnoseTimer?.cancel();
      _androidDiagnoseTimer = null;
      _androidDiagnoseShown = false;
      return;
    }
    if (phase == SingboxRunPhase.running) {
      if (_androidDiagnoseTimer != null || _androidDiagnoseShown) {
        return;
      }
      _androidDiagnoseShown = true;
      _androidDiagnoseTimer = Timer(const Duration(milliseconds: 800), () async {
        if (!mounted) return;
        _androidDiagnoseTimer = null;
        try {
          await _showAndroidRuntimeDiagnosis();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('获取诊断失败：$e')),
          );
        }
      });
      return;
    }

    // 离开 running 后，取消等待中的诊断并允许下次连接重新显示
    _androidDiagnoseTimer?.cancel();
    _androidDiagnoseTimer = null;
    if (phase != SingboxRunPhase.starting) {
      _androidDiagnoseShown = false;
    }
  }

  void _showAnnouncementDetail(String body) {
    if (!mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('公告详情'),
          content: SingleChildScrollView(
            child: SelectableText(
              body,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _openAllNodesSheet() {
    ref.read(nodeListProvider).when(
      data: (nodes) {
        if (!mounted) {
          return;
        }
        if (nodes.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无节点')),
          );
          return;
        }
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        '全部节点',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.5,
                      child: Consumer(
                        builder: (context, ref, _) {
                          final stats = ref.watch(userStatsProvider).asData?.value;
                          final runPhase = ref.watch(singboxStateProvider).asData?.value.phase;
                          scheduleNodePings(
                            ref,
                            nodes,
                            stats,
                            enabled: runPhase != SingboxRunPhase.running,
                          );
                          final selectedId = ref.watch(selectedNodeIdProvider);
                          final pingMap = ref.watch(nodePingProvider);
                          const primaryTeal = Color(0xFF4DB6AC);
                          return ListView.separated(
                            itemCount: nodes.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final n = nodes[i];
                              final sel = selectedId == n.id;
                              final flag = CountryFlag.emojiForNodeName(n.name);
                              final measured = pingMap[n.id];
                              final hasMeasured = pingMap.containsKey(n.id);
                              final status = _nodeLatencyLabel(
                                panelPingMs: n.pingMs,
                                measuredPingMs: measured,
                                hasMeasured: hasMeasured,
                              );
                              return ListTile(
                                leading: Text(flag ?? '🌐', style: const TextStyle(fontSize: 24)),
                                title: Text(n.name),
                                subtitle: Text(
                                  status.$1,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: status.$2),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(status.$3, size: 18, color: status.$2),
                                    if (sel) ...[
                                      const SizedBox(width: 10),
                                      const Icon(Icons.check_circle, color: primaryTeal),
                                    ],
                                  ],
                                ),
                                selected: sel,
                                onTap: () async {
                                  await ref.read(selectedNodeIdProvider.notifier).set(n.id);
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('节点加载中…')),
        );
      },
      error: (e, _) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is UserApiException ? e.message : '$e')),
        );
      },
    );
  }

  (String, Color, IconData) _nodeLatencyLabel({
    required int? panelPingMs,
    required int? measuredPingMs,
    required bool hasMeasured,
  }) {
    if (measuredPingMs != null) {
      return ('延迟：$measuredPingMs ms', Colors.green, Icons.speed_rounded);
    }
    if (panelPingMs != null) {
      return ('延迟：$panelPingMs ms', Colors.lightBlue, Icons.speed_rounded);
    }
    if (hasMeasured) {
      return ('延迟：不可达', Colors.redAccent, Icons.error_outline);
    }
    return ('延迟：待检测', Colors.orange, Icons.schedule);
  }

  String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) {
      return '0 B/s';
    }
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
    final kb = bytesPerSec / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB/s';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB/s';
  }

  Future<void> _refreshRealtimeSpeed() async {
    final snap = await readMacNetworkBytes();
    if (!mounted || snap == null) {
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastSpeedSampleAt;
    final lastRx = _lastRxBytes;
    final lastTx = _lastTxBytes;
    _lastSpeedSampleAt = now;
    _lastRxBytes = snap.$1;
    _lastTxBytes = snap.$2;
    if (lastAt == null || lastRx == null || lastTx == null) {
      return;
    }
    final elapsedMs = now.difference(lastAt).inMilliseconds;
    if (elapsedMs <= 0) {
      return;
    }
    final secs = elapsedMs / 1000.0;
    final down = (snap.$1 - lastRx) / secs;
    final up = (snap.$2 - lastTx) / secs;
    setState(() {
      _downBytesPerSec = down.isFinite && down > 0 ? down : 0;
      _upBytesPerSec = up.isFinite && up > 0 ? up : 0;
    });
  }

  void _syncConnectionTimer(SingboxRunPhase phase) {
    if (phase == SingboxRunPhase.running) {
      _connectedAt ??= DateTime.now();
      unawaited(_refreshRealtimeSpeed());
      _accountStatusTimer ??= Timer.periodic(_connectedStatsRefreshInterval, (_) {
        unawaited(_refreshConnectedAccountStatus());
      });
      _connTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _connectedAt == null) {
          return;
        }
        setState(() {
          _elapsed = DateTime.now().difference(_connectedAt!);
        });
        unawaited(_refreshRealtimeSpeed());
      });
    } else {
      _connTimer?.cancel();
      _connTimer = null;
      _accountStatusTimer?.cancel();
      _accountStatusTimer = null;
      _connectedAt = null;
      _elapsed = Duration.zero;
      _lastSpeedSampleAt = null;
      _lastRxBytes = null;
      _lastTxBytes = null;
      _downBytesPerSec = 0;
      _upBytesPerSec = 0;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<PanelUserStats?> _loadUserStatsForConnection() async {
    final cached = ref.read(userStatsProvider).valueOrNull;
    final refreshedAt = _lastUserStatsRefreshAt;
    final cacheFresh = cached != null &&
        refreshedAt != null &&
        DateTime.now().difference(refreshedAt) <= _userStatsCacheTtl;
    if (cacheFresh) {
      return cached;
    }
    return _refreshUserStats();
  }

  Future<PanelUserStats?> _refreshUserStats() async {
    await ref.read(userStatsProvider.notifier).refresh();
    return ref.read(userStatsProvider).valueOrNull;
  }

  Future<void> _refreshConnectedAccountStatus() async {
    final stats = await _refreshUserStats();
    if (stats == null) {
      return;
    }
    await _ensureAccountAccess(
      stats,
      showPrompt: true,
      stopIfRunning: true,
    );
  }

  Future<void> _showAndroidRuntimeDiagnosis() async {
    if (!mounted || !isAndroid) {
      return;
    }
    try {
      const ch = MethodChannel('yuqianhe/singbox_android');
      final map = await ch.invokeMethod('diagnose').timeout(const Duration(seconds: 8));
      final text = map is Map
          ? map.entries.map((e) => '${e.key}=${e.value}').join('\n')
          : '$map';
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Android 运行诊断'),
          content: SingleChildScrollView(
            child: SelectableText(text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取 Android 运行诊断失败：$e')),
      );
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> _connectSelectedNode({required bool showSuccessSnack}) async {
    final c = ref.read(singboxControllerProvider);
    final prefs = ref.read(clientUiPrefsProvider);
    final node = ref.read(selectedPanelNodeProvider);
    if (node == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择节点')),
        );
      }
      return false;
    }
    final stats = await _loadUserStatsForConnection();
    if (stats == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取用户信息，请下拉刷新后重试')),
        );
      }
      return false;
    }
    if (!await _ensureAccountAccess(
      stats,
      showPrompt: true,
      stopIfRunning: false,
    )) {
      return false;
    }

    final cfg = buildSingboxConfigForPanelNode(
      node: node,
      stats: stats,
      includeTun: tunInboundSupported && prefs.tunMode,
    );
    if (!cfg.isOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(cfg.errorMessage ?? '配置生成失败')),
        );
      }
      return false;
    }
    await c.start(cfg.json!);
    final after = c.currentState;
    if (after.phase == SingboxRunPhase.error) {
      final msg = after.message ?? '连接失败';
      if (mounted) {
        final isDetailed = msg.contains('\n');
        if (isDetailed) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('连接失败诊断'),
              content: SingleChildScrollView(
                child: SelectableText(msg),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
      return false;
    }
    if (after.phase == SingboxRunPhase.running && !prefs.tunMode) {
      try {
        if (!prefs.globalProxy) {
          await ref.read(clientUiPrefsProvider.notifier).setGlobalProxy(true);
        }
        await applySingboxGlobalHttpProxy(enable: true);
      } catch (e) {
        await c.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('启用系统代理失败：$e'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return false;
      }
    }
    if (showSuccessSnack && mounted && after.phase == SingboxRunPhase.running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已连接：已通过本机混合端口代理连通外网检测。'),
          duration: Duration(seconds: 5),
        ),
      );
    }
    return after.phase == SingboxRunPhase.running;
  }

  /// 已连接时切换节点：自动断开并重连到新节点。
  Future<void> _reconnectAfterNodeSwitch() async {
    final c = ref.read(singboxControllerProvider);
    final prefs = ref.read(clientUiPrefsProvider);
    if (prefs.globalProxy) {
      await applySingboxGlobalHttpProxy(enable: false);
    }
    await c.stop();
    if (!mounted) {
      return;
    }
    final ok = await _connectSelectedNode(showSuccessSnack: false);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已切换节点并自动重连' : '切换节点后自动重连失败'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _logout() async {
    ref.invalidate(nodeListProvider);
    ref.invalidate(userStatsProvider);
    ref.read(nodePingProvider.notifier).clear();
    await applySingboxGlobalHttpProxy(enable: false);
    await ref.read(singboxControllerProvider).stop();
    await ref.read(authNotifierProvider.notifier).logout();
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      ref.read(nodeListProvider.notifier).refresh(),
      ref.read(userStatsProvider.notifier).refresh(),
    ]);
    final nodes = ref.read(nodeListProvider).asData?.value;
    final stats = ref.read(userStatsProvider).asData?.value;
    if (nodes != null && nodes.isNotEmpty && stats != null) {
      await ref.read(nodePingProvider.notifier).refreshNow(nodes, stats);
    } else {
      ref.read(nodePingProvider.notifier).clear();
    }
  }

  Future<void> _openExternal(String url) async {
    final u = Uri.tryParse(url);
    if (u == null) {
      return;
    }
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showAccessBlockedDialog(PanelUserStats stats) async {
    if (!mounted || _accessBlockedDialogOpen) {
      return;
    }
    _accessBlockedDialogOpen = true;
    final baseUrl = ref.read(panelBaseUrlProvider) ?? '';
    final origin = baseUrl.isEmpty ? '' : Uri.parse(baseUrl).origin;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('当前账号无法使用代理'),
          content: Text('${stats.accessBlockedReason}，请前往官网充值购买流量套餐或续费后再使用。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            if (origin.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openExternal(origin);
                },
                child: const Text('官网'),
              ),
            if (origin.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openExternal('$origin/#/user/shop');
                },
                child: const Text('购买套餐'),
              ),
          ],
        ),
      );
    } finally {
      _accessBlockedDialogOpen = false;
    }
  }

  Future<bool> _ensureAccountAccess(
    PanelUserStats stats, {
    required bool showPrompt,
    required bool stopIfRunning,
  }) async {
    if (!stats.isAccessBlocked) {
      return true;
    }
    final c = ref.read(singboxControllerProvider);
    final phase = c.currentState.phase;
    if (stopIfRunning &&
        (phase == SingboxRunPhase.running || phase == SingboxRunPhase.starting)) {
      await applySingboxGlobalHttpProxy(enable: false);
      await c.stop();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${stats.accessBlockedReason}，请前往官网充值购买流量套餐或续费后再使用。'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (showPrompt) {
      await _showAccessBlockedDialog(stats);
    }
    return false;
  }

  void _openMainMenu() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _powerTap(SingboxRunPhase phase) async {
    if (_powerActionLocked ||
        phase == SingboxRunPhase.starting ||
        phase == SingboxRunPhase.stopping) {
      return;
    }
    final c = ref.read(singboxControllerProvider);
    final startedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _powerActionLocked = true;
      });
    }
    try {
      if (phase == SingboxRunPhase.running) {
        await applySingboxGlobalHttpProxy(enable: false);
        await c.stop();
        return;
      }
      await _connectSelectedNode(showSuccessSnack: true);
    } finally {
      final remaining = _powerActionMinLockDuration - DateTime.now().difference(startedAt);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (mounted) {
        setState(() {
          _powerActionLocked = false;
        });
      }
    }
  }

  void _cycleTheme() {
    final cur = ref.read(clientUiPrefsProvider).themeMode;
    final next = cur == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    ref.read(clientUiPrefsProvider.notifier).setThemeMode(next);
  }

  Future<void> _showSettings() async {
    final base = ref.read(panelBaseUrlProvider) ?? '';
    final ctrl = TextEditingController(text: base);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('设置'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('当前面板地址', style: Theme.of(ctx).textTheme.labelSmall),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://…',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Text(
                  '修改后请保存并重启应用或重新登录以确保 Cookie 一致。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            FilledButton(
              onPressed: () async {
                final u = ctrl.text.trim();
                if (u.isNotEmpty) {
                  await ref.read(authNotifierProvider.notifier).setPanelBaseUrl(u);
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(nodeListProvider);
    final statsAsync = ref.watch(userStatsProvider);
    final singboxAsync = ref.watch(singboxStateProvider);
    final selectedNode = ref.watch(selectedPanelNodeProvider);
    final uiPrefs = ref.watch(clientUiPrefsProvider);
    final baseUrl = ref.watch(panelBaseUrlProvider) ?? '';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const primaryTeal = Color(0xFF4DB6AC);

    ref.listen(nodeListProvider, (prev, next) {
      next.whenData((nodes) {
        unawaited(ref.read(selectedNodeIdProvider.notifier).ensureDefault(nodes));
      });
    });
    ref.listen(singboxStateProvider, (prev, next) {
      next.whenData((s) {
        _syncConnectionTimer(s.phase);
        unawaited(_maybeShowAndroidDiagnose(s.phase));
        if (s.phase == SingboxRunPhase.error) {
          unawaited(applySingboxGlobalHttpProxy(enable: false));
          // 从「已连接」退出的错误（如 sing-box 崩溃）在此提示；首次连接失败由 _powerTap 提示以免重复
          final msg = s.message;
          final wasRunning = prev?.asData?.value.phase == SingboxRunPhase.running;
          if (wasRunning && msg != null && msg.isNotEmpty && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), duration: const Duration(seconds: 8)),
            );
          }
        }
      });
    });
    ref.listen(userStatsProvider, (prev, next) {
      final prevStats = prev?.asData?.value;
      next.whenData((stats) {
        _lastUserStatsRefreshAt = DateTime.now();
        final becameBlocked = stats.isAccessBlocked &&
            ((prevStats?.isAccessBlocked ?? false) == false ||
                prevStats?.accessBlockedReason != stats.accessBlockedReason);
        final phase = ref.read(singboxControllerProvider).currentState.phase;
        if (!becameBlocked) {
          return;
        }
        if (phase != SingboxRunPhase.running && phase != SingboxRunPhase.starting) {
          return;
        }
        unawaited(_ensureAccountAccess(
          stats,
          showPrompt: true,
          stopIfRunning: true,
        ));
      });
    });

    ref.listen<int?>(selectedNodeIdProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      final phase = ref.read(singboxControllerProvider).currentState.phase;
      if (phase != SingboxRunPhase.running && phase != SingboxRunPhase.starting) {
        return;
      }
      unawaited(_reconnectAfterNodeSwitch());
    });

    final singboxSnap = singboxAsync.maybeWhen(data: (s) => s, orElse: () => null);
    final phase = singboxSnap?.phase ?? SingboxRunPhase.stopped;
    final singboxMessage = singboxSnap?.message;
    nodesAsync.whenData((nodes) {
      scheduleNodePings(
        ref,
        nodes,
        statsAsync.asData?.value,
        enabled: phase != SingboxRunPhase.running,
      );
    });
    final pingMap = ref.watch(nodePingProvider);
    final currentNodeStatus = selectedNode == null
        ? ('未选择节点', theme.colorScheme.outline, Icons.help_outline)
        : _nodeLatencyLabel(
            panelPingMs: selectedNode.pingMs,
            measuredPingMs: pingMap[selectedNode.id],
            hasMeasured: pingMap.containsKey(selectedNode.id),
          );
    final officialAction = () {
      if (baseUrl.isEmpty) {
        return;
      }
      final o = Uri.parse(baseUrl).origin;
      _openExternal(o);
    };
    final plansAction = () {
      if (baseUrl.isEmpty) {
        return;
      }
      final o = Uri.parse(baseUrl).origin;
      _openExternal('$o/#/user/shop');
    };

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.brightness == Brightness.light ? const Color(0xFFD7F6F2) : theme.scaffoldBackgroundColor,
      drawer: _MainMenuDrawer(
        onTheme: _cycleTheme,
        onOfficial: officialAction,
        onSettings: _showSettings,
        onPlans: plansAction,
        onLogout: _logout,
        isDark: theme.brightness == Brightness.dark,
        versionLabel: kAppVersionLabel,
      ),
      bottomNavigationBar: const _BottomNavBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: LayoutBuilder(
            builder: (context, c) {
              final bodyWidth = c.maxWidth > 430 ? 430.0 : c.maxWidth;
              return Center(
                child: SizedBox(
                  width: bodyWidth,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _HeaderBar(
                    onMenu: _openMainMenu,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _AnnouncementCard(
                    announcement: statsAsync.maybeWhen(
                      data: (s) => s.announcementPlain,
                      orElse: () => null,
                    ),
                    announcementLoading: statsAsync.isLoading,
                    onAnnouncementTap: () {
                      final stats = ref.read(userStatsProvider);
                      final body = stats.asData?.value.announcementPlain;
                      if (body != null && body.trim().isNotEmpty) {
                        _showAnnouncementDetail(body.trim());
                      }
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final narrow = c.maxWidth < 720;
                      return statsAsync.when(
                        loading: () => const _DashboardSkeleton(),
                        error: (e, _) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              e is UserApiException ? e.message : '$e',
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        ),
                        data: (stats) => _DashboardPanel(
                          narrow: narrow,
                          stats: stats,
                          phase: phase,
                          singboxErrorMessage: singboxMessage,
                          elapsedLabel: _fmtDuration(_elapsed),
                          downSpeedLabel: _fmtSpeed(_downBytesPerSec),
                          upSpeedLabel: _fmtSpeed(_upBytesPerSec),
                          statusNodeName: selectedNode?.name,
                          currentNodeStatus: currentNodeStatus,
                          onPower: () => _powerTap(phase),
                          powerLocked: _powerActionLocked,
                          onRefreshTraffic: _refreshAll,
                          onOpenNodes: _openAllNodesSheet,
                          globalProxy: uiPrefs.globalProxy,
                          tunMode: uiPrefs.tunMode,
                          tunInboundSupported: tunInboundSupported,
                          onGlobal: (v) => ref.read(clientUiPrefsProvider.notifier).setGlobalProxy(v),
                          onTun: (v) => ref.read(clientUiPrefsProvider.notifier).setTunMode(v),
                          primaryTeal: primaryTeal,
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: const SizedBox.shrink(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.onMenu,
  });

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onMenu,
                    tooltip: '菜单',
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                    icon: const Icon(Icons.menu_rounded),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: const AssetImage('assets/images/yuqianhe_logo.png'),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ],
              ),
              IgnorePointer(
                child: RichText(
                  text: TextSpan(
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    children: [
                      const TextSpan(text: '宇千鹤'),
                      TextSpan(
                        text: 'VPN',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 200,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _MainMenuDrawer extends StatelessWidget {
  const _MainMenuDrawer({
    required this.onTheme,
    required this.onOfficial,
    required this.onSettings,
    required this.onPlans,
    required this.onLogout,
    required this.isDark,
    required this.versionLabel,
  });

  final VoidCallback onTheme;
  final VoidCallback onOfficial;
  final VoidCallback onSettings;
  final VoidCallback onPlans;
  final VoidCallback onLogout;
  final bool isDark;
  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void tap(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/yuqianhe_logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '宇千鹤',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              title: const Text('主题'),
              onTap: () => tap(onTheme),
            ),
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: const Text('官网'),
              onTap: () => tap(onOfficial),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () => tap(onSettings),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded),
              title: const Text('套餐'),
              onTap: () => tap(onPlans),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '版本号 $versionLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('退出'),
              onTap: () => tap(onLogout),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DashboardPanel extends StatefulWidget {
  const _DashboardPanel({
    required this.narrow,
    required this.stats,
    required this.phase,
    this.singboxErrorMessage,
    required this.elapsedLabel,
    required this.downSpeedLabel,
    required this.upSpeedLabel,
    required this.statusNodeName,
    required this.currentNodeStatus,
    required this.onPower,
    required this.powerLocked,
    required this.onRefreshTraffic,
    required this.onOpenNodes,
    required this.globalProxy,
    required this.tunMode,
    required this.tunInboundSupported,
    required this.onGlobal,
    required this.onTun,
    required this.primaryTeal,
  });

  final bool narrow;
  final PanelUserStats stats;
  final SingboxRunPhase phase;
  final String? singboxErrorMessage;
  final String elapsedLabel;
  final String downSpeedLabel;
  final String upSpeedLabel;
  final String? statusNodeName;
  final (String, Color, IconData) currentNodeStatus;
  final VoidCallback onPower;
  final bool powerLocked;
  final VoidCallback onRefreshTraffic;
  final VoidCallback onOpenNodes;
  final bool globalProxy;
  final bool tunMode;
  final bool tunInboundSupported;
  final ValueChanged<bool> onGlobal;
  final ValueChanged<bool> onTun;
  final Color primaryTeal;

  @override
  State<_DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<_DashboardPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _DashboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.phase == SingboxRunPhase.running) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = widget.phase == SingboxRunPhase.running;
    final busy = widget.powerLocked ||
        widget.phase == SingboxRunPhase.starting ||
        widget.phase == SingboxRunPhase.stopping;
    final status = running
        ? '已连接'
        : widget.phase == SingboxRunPhase.error
            ? '连接失败'
            : '未连接';
    final statusColor = running
        ? const Color(0xFF4F8CFF)
        : widget.phase == SingboxRunPhase.error
            ? theme.colorScheme.error
            : theme.colorScheme.outline;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryStatTile(
                    label: '连接状态',
                    value: status,
                    valueColor: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryStatTile(
                    label: '连接时间',
                    value: running ? widget.elapsedLabel : '00:00:00',
                    mono: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final pulse = _pulseController.value;
                final outerSize = widget.narrow ? 210.0 : 240.0;
                final innerSize = widget.narrow ? 168.0 : 188.0;
                final buttonSize = widget.narrow ? 96.0 : 110.0;

                return SizedBox(
                  width: outerSize,
                  height: outerSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (running)
                        Transform.scale(
                          scale: 1.0 + pulse * 0.16,
                          child: Container(
                            width: outerSize,
                            height: outerSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.primaryTeal.withValues(alpha: 0.08 - pulse * 0.04),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: outerSize,
                          height: outerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.primaryTeal.withValues(alpha: 0.08),
                          ),
                        ),
                      Transform.scale(
                        scale: running ? 0.98 + pulse * 0.06 : 1,
                        child: Container(
                          width: innerSize,
                          height: innerSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.primaryTeal.withValues(alpha: running ? 0.16 : 0.12),
                          ),
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: busy ? null : widget.onPower,
                          child: Transform.scale(
                            scale: running ? 1 + pulse * 0.035 : 1,
                            child: Ink(
                              width: buttonSize,
                              height: buttonSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: running
                                      ? [const Color(0xFF69B3FF), const Color(0xFF6A5BFF)]
                                      : [const Color(0xFFFF6E6E), const Color(0xFFE53935)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(28),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(
                                      Icons.power_settings_new_rounded,
                                      size: 42,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _UsageStatTile(
                      label: '剩余流量',
                      value: widget.stats.remainingTrafficCompact,
                      icon: Icons.data_usage_rounded,
                      color: const Color(0xFF35D36D),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: _UsageStatTile(
                      label: '剩余天数',
                      value: widget.stats.remainingDaysLabel(),
                      icon: Icons.calendar_today_rounded,
                      color: const Color(0xFF5B9DFF),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('全局代理', style: theme.textTheme.labelMedium),
                            const SizedBox(width: 4),
                            _CompactSwitch(
                              value: widget.globalProxy,
                              onChanged: widget.onGlobal,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('TUN 模式', style: theme.textTheme.labelMedium),
                            const SizedBox(width: 4),
                            _CompactSwitch(
                              value: widget.tunInboundSupported && widget.tunMode,
                              onChanged: widget.tunInboundSupported ? widget.onTun : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!widget.tunInboundSupported)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '当前端未启用 TUN，请使用全局代理',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SpeedTile(
                      label: '下载',
                      value: widget.downSpeedLabel,
                      color: const Color(0xFF35D36D),
                      icon: Icons.south_rounded,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 26,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: _SpeedTile(
                      label: '上传',
                      value: widget.upSpeedLabel,
                      color: const Color(0xFF5B9DFF),
                      icon: Icons.north_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onOpenNodes,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFF5B9DFF)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.statusNodeName == null || widget.statusNodeName!.isEmpty
                                  ? '当前节点：未选择'
                                  : '当前节点：${widget.statusNodeName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.currentNodeStatus.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: widget.currentNodeStatus.$2,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '刷新数据',
                        onPressed: widget.onRefreshTraffic,
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.outline,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.phase == SingboxRunPhase.error &&
                widget.singboxErrorMessage != null &&
                widget.singboxErrorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.singboxErrorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryStatTile extends StatelessWidget {
  const _SummaryStatTile({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: valueColor ?? theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageStatTile extends StatelessWidget {
  const _UsageStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.8,
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline),
          ),
          const Spacer(),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.announcementLoading,
    required this.onAnnouncementTap,
  });

  /// 面板 [getUserInfo] 中最新一条公告（`Ann::orderBy('date','desc')->first()`）。
  final String? announcement;
  final bool announcementLoading;
  final VoidCallback onAnnouncementTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: InkWell(
          onTap: onAnnouncementTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: announcementLoading
                      ? SizedBox(
                          height: 20,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        )
                      : (announcement != null && announcement!.trim().isNotEmpty)
                          ? AnnouncementMarquee(
                              text: announcement!.trim(),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              onTap: onAnnouncementTap,
                            )
                          : Text(
                              '暂无公告',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(IconData icon, bool active) {
      return Icon(
        icon,
        size: 20,
        color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            item(Icons.home_rounded, true),
            item(Icons.public_rounded, false),
            item(Icons.workspace_premium_rounded, false),
            item(Icons.notifications_none_rounded, false),
          ],
        ),
      ),
    );
  }
}
