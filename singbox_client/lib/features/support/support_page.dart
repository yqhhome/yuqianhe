import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/support/external_browser_launcher.dart';

const _kCrispWebsiteId = '2f0da308-f1ec-4d1b-96e7-c7494bac9f58';
const _kCrispUrl = 'https://go.crisp.chat/chat/embed/?website_id=$_kCrispWebsiteId';

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({
    super.key,
    this.bottomNavigationBar,
    this.onBack,
  });

  final Widget? bottomNavigationBar;
  final VoidCallback? onBack;

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  bool _opening = false;

  Future<void> _openCrisp() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      final ok = await ExternalBrowserLauncher.openUrl(_kCrispUrl);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开客服聊天页面')),
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '在线客服',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.support_agent_rounded,
                        size: 74,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '联系客服',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '点击下方按钮，将优先使用 Google Chrome 打开 Crisp 客服聊天；如果设备没有安装 Chrome，则回退系统默认浏览器。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _opening ? null : _openCrisp,
                        icon: const Icon(Icons.open_in_browser_rounded),
                        label: _opening
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('打开客服聊天'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
