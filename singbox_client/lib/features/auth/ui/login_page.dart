import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/support/external_browser_launcher.dart';
import '../../../core/settings/panel_url_hints.dart';
import '../../../core/ui/brand_logo.dart';
import '../../../data/models/login_request.dart';
import '../application/auth_notifier.dart';
import '../application/auth_state.dart';
import 'password_recovery_page.dart';

/// First screen: email + password + login / register. Server URL is in ⚙️ only.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwdCtrl = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _openServerSettings() async {
    final current = ref.read(panelBaseUrlProvider) ?? '';
    final ctrl = TextEditingController(text: current);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('服务器地址'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '填写与浏览器打开用户中心相同的根地址（支持 http 或 https）。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '在 Android / iPhone 上访问你电脑上的面板时，请使用电脑的局域网 IP，'
                  '例如 http://192.168.1.10:8787；不要使用 127.0.0.1 或 localhost。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: '面板根地址',
                    hintText: 'https://panel.example.com 或 http://192.168.x.x:8787',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).logout();
                await ref.read(appServicesProvider).panelSettings.setBaseUrl('');
                ref.read(panelBaseUrlProvider.notifier).set(null);
                ctrl.clear();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('清除'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (saved == true && mounted) {
      final url = ctrl.text.trim();
      if (url.isNotEmpty) {
        final warn = panelUrlLocalhostWarning(url);
        if (warn != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(warn)),
          );
        } else {
          await ref.read(authNotifierProvider.notifier).setPanelBaseUrl(url);
        }
      }
    }
    // Dialog 关闭后子树可能仍在卸载；下一帧再 dispose，避免 TextField 仍监听已 dispose 的 controller。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.dispose();
    });
  }

  Future<void> _submit() async {
    final base = ref.read(panelBaseUrlProvider);
    if (base == null || base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在右上角设置中填写服务器地址')),
      );
      return;
    }
    final email = _emailCtrl.text.trim();
    final password = _passwdCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮箱和密码不能为空')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).login(
            LoginRequest(
              email: email,
              password: password,
              rememberMe: true,
            ),
          );
      if (!mounted) {
        return;
      }
      final s = ref.read(authNotifierProvider);
      if (s.status != AuthStatus.authenticated && s.lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.lastError!)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _goRegister() async {
    final base = ref.read(panelBaseUrlProvider);
    if (base == null || base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在右上角设置中填写服务器地址')),
      );
      return;
    }
    final ok = await ExternalBrowserLauncher.openUrl('${Uri.parse(base).origin}/auth/register');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开注册页面')),
      );
    }
  }

  void _goPasswordRecovery() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PasswordRecoveryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('宇千鹤 · 登录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '服务器地址',
            onPressed: _openServerSettings,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 820 : 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandLogo(imageSize: 86),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: '邮箱',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwdCtrl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: '密码',
                            border: const OutlineInputBorder(),
                            isDense: false,
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 52,
                              minHeight: 48,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              style: IconButton.styleFrom(
                                foregroundColor: Theme.of(context).colorScheme.primary,
                              ),
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                size: 26,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          onSubmitted: (_) => _busy ? null : _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _goPasswordRecovery,
                            child: const Text('找回密码'),
                          ),
                        ),
                        if (auth.lastError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            auth.lastError!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('登录'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _busy ? null : _goRegister,
                          child: const Text('注册'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
