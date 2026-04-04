import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/ui/auth_gate.dart';
import 'features/home/application/client_ui_prefs_notifier.dart';

class SingboxClientApp extends ConsumerWidget {
  const SingboxClientApp({super.key});

  static const _teal = Color(0xFF4DB6AC);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(clientUiPrefsProvider).themeMode;
    return MaterialApp(
      title: 'Sing-Box Client',
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _teal, brightness: Brightness.light),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
