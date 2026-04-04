import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_notifier.dart';
import '../home/application/user_stats_notifier.dart';
import '../../data/datasources/user_remote_datasource.dart';

class AnnouncementPage extends ConsumerWidget {
  const AnnouncementPage({super.key, this.bottomNavigationBar});

  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(userStatsProvider);

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? const Color(0xFFD7F6F2)
          : theme.scaffoldBackgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(userStatsProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const _AnnouncementHeader(),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: statsAsync.when(
                    loading: () => const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          e is UserApiException ? e.message : '$e',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    data: (stats) {
                      final text = stats.announcementPlain?.trim() ?? '';
                      if (text.isEmpty) {
                        return const _AnnouncementEmptyState();
                      }
                      return _AnnouncementLatestCard(text: text);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementHeader extends ConsumerWidget {
  const _AnnouncementHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseUrl = ref.watch(panelBaseUrlProvider);
    final host = baseUrl == null || baseUrl.isEmpty ? '未设置面板地址' : Uri.parse(baseUrl).host;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '公告',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '当前仅显示面板最新一条公告，来源：$host',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementLatestCard extends StatelessWidget {
  const _AnnouncementLatestCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnnouncementDetailPage(text: text),
          ),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.notifications_active_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '最新公告',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '点击查看详情',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnnouncementDetailPage extends StatelessWidget {
  const AnnouncementDetailPage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('公告详情')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SelectableText(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementEmptyState extends StatelessWidget {
  const _AnnouncementEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 14),
            Text(
              '暂无公告',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '面板当前没有可展示的最新公告。',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
