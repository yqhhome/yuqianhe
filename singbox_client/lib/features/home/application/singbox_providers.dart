import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/singbox/platform_info.dart';
import '../../../core/singbox/singbox_android_controller.dart';
import '../../../core/singbox/singbox_controller.dart';
import '../../../core/singbox/singbox_macos_controller.dart';
import '../../../core/singbox/singbox_state.dart';
import '../../../core/singbox/singbox_stub_controller.dart';
import '../../../core/singbox/singbox_windows_controller.dart';

/// macOS / Android / Windows 使用各自真实控制器；其它平台仍为占位实现。
final singboxControllerProvider = Provider<SingboxController>((ref) {
  final SingboxController c;
  if (!kIsWeb && isMacOS) {
    c = SingboxMacosController();
  } else if (!kIsWeb && isAndroid) {
    c = SingboxAndroidController();
  } else if (!kIsWeb && isWindows) {
    c = SingboxWindowsController();
  } else {
    c = SingboxStubController();
  }
  ref.onDispose(c.dispose);
  return c;
});

/// 当前 sing-box 状态（含首次 [currentState]）。
final singboxStateProvider = StreamProvider<SingboxState>((ref) async* {
  final c = ref.watch(singboxControllerProvider);
  yield c.currentState;
  yield* c.stateStream;
});
