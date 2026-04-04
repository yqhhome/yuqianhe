import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/support/external_browser_launcher.dart';
import '../../../core/ui/brand_logo.dart';
import '../application/auth_notifier.dart';

class PasswordRecoveryPage extends ConsumerStatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  ConsumerState<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends ConsumerState<PasswordRecoveryPage> {
  bool _opening = false;

  Future<void> _openResetInBrowser() async {
    final base = ref.read(panelBaseUrlProvider);
    if (base == null || base.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先返回登录页设置服务器地址')),
      );
      return;
    }
    setState(() => _opening = true);
    try {
      final uri = Uri.parse('$base/password/reset');
      final ok = await ExternalBrowserLauncher.openUrl(uri.toString());
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开重置页面：$uri')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('找回密码')),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 820;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 780 : 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandLogo(imageSize: 84),
                        const SizedBox(height: 14),
                        Text(
                          '请在面板网页完成密码重置',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '客户端将打开浏览器进入重置密码页面，操作完成后返回客户端登录即可。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _opening ? null : _openResetInBrowser,
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: _opening
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('打开重置页面'),
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

