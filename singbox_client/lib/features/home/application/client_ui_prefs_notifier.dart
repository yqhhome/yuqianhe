import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/singbox/tun_inbound_support.dart';
import '../../auth/application/auth_notifier.dart';

const _kGlobalProxy = 'client_global_proxy';
const _kTunMode = 'client_tun_mode';
const _kThemeMode = 'client_theme_mode';

final clientUiPrefsProvider = NotifierProvider<ClientUiPrefsNotifier, ClientUiPrefs>(ClientUiPrefsNotifier.new);

class ClientUiPrefs {
  const ClientUiPrefs({
    required this.globalProxy,
    required this.tunMode,
    required this.themeMode,
  });

  final bool globalProxy;
  final bool tunMode;
  final ThemeMode themeMode;

  ClientUiPrefs copyWith({
    bool? globalProxy,
    bool? tunMode,
    ThemeMode? themeMode,
  }) {
    return ClientUiPrefs(
      globalProxy: globalProxy ?? this.globalProxy,
      tunMode: tunMode ?? this.tunMode,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class ClientUiPrefsNotifier extends Notifier<ClientUiPrefs> {
  @override
  ClientUiPrefs build() {
    final p = ref.read(appServicesProvider).prefs;
    final storedTun = p.getBool(_kTunMode) ?? false;
    var tun = storedTun && tunInboundSupported;
    if (storedTun && !tunInboundSupported) {
      Future.microtask(() async {
        await p.setBool(_kTunMode, false);
      });
    }
    return ClientUiPrefs(
      globalProxy: p.getBool(_kGlobalProxy) ?? true,
      tunMode: tun,
      themeMode: _readTheme(p.getString(_kThemeMode)),
    );
  }

  ThemeMode _readTheme(String? v) {
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setGlobalProxy(bool v) async {
    await ref.read(appServicesProvider).prefs.setBool(_kGlobalProxy, v);
    state = state.copyWith(globalProxy: v);
  }

  Future<void> setTunMode(bool v) async {
    if (!tunInboundSupported) {
      return;
    }
    await ref.read(appServicesProvider).prefs.setBool(_kTunMode, v);
    state = state.copyWith(tunMode: v);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    final s = switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await ref.read(appServicesProvider).prefs.setString(_kThemeMode, s);
    state = state.copyWith(themeMode: m);
  }
}
