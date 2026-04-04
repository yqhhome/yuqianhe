import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/application/auth_notifier.dart';
import '../../core/api/api_paths.dart';
import '../../data/datasources/user_remote_datasource.dart';

final announcementListProvider = FutureProvider<List<AnnouncementListItem>>((
  ref,
) async {
  final base = ref.watch(panelBaseUrlProvider);
  if (base == null || base.isEmpty) {
    return const [];
  }
  final services = ref.watch(appServicesProvider);
  final dio = services.createDio(base);
  final res = await dio.get<dynamic>(
    '${ApiPaths.userHome}/announcement',
    options: Options(
      responseType: ResponseType.bytes,
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
    ),
  );
  final code = res.statusCode ?? 0;
  if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
    throw UserApiException('登录已过期，请重新登录');
  }
  final data = res.data;
  final bytes = data is List<int> ? data : utf8.encode(data?.toString() ?? '');
  final raw = utf8.decode(bytes);
  return AnnouncementListItem.parseHtml(raw);
});

class AnnouncementListItem {
  const AnnouncementListItem({
    required this.id,
    required this.dateText,
    required this.preview,
    required this.content,
  });

  final int id;
  final String dateText;
  final String preview;
  final String content;

  static List<AnnouncementListItem> parseHtml(String raw) {
    final rows = RegExp(
      r'<tr>\s*<td>\s*<a[^>]*data-ann-content="([^"]+)"[^>]*>.*?</a>\s*</td>\s*<td>#(\d+)</td>\s*<td>([^<]+)</td>\s*<td>(.*?)</td>\s*</tr>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(raw);

    final out = <AnnouncementListItem>[];
    for (final row in rows) {
      final encoded = row.group(1) ?? '';
      final id = int.tryParse(row.group(2) ?? '') ?? 0;
      final date = _cleanText(row.group(3) ?? '');
      final preview = _cleanText(row.group(4) ?? '');
      final content = _cleanText(Uri.decodeComponent(encoded));
      if (content.isEmpty) {
        continue;
      }
      out.add(
        AnnouncementListItem(
          id: id,
          dateText: date,
          preview: preview.isEmpty ? content : preview,
          content: content,
        ),
      );
    }
    return out;
  }

  static String _cleanText(String input) {
    var text = input
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text;
  }
}

class AnnouncementPage extends ConsumerWidget {
  const AnnouncementPage({super.key, this.bottomNavigationBar});

  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final listAsync = ref.watch(announcementListProvider);

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
                  child: listAsync.when(
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
                    data: (items) {
                      if (items.isEmpty) {
                        return const _AnnouncementEmptyState();
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            _AnnouncementListCard(item: items[i]),
                            if (i != items.length - 1) const SizedBox(height: 14),
                          ],
                        ],
                      );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '公告列表',
        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AnnouncementListCard extends StatelessWidget {
  const _AnnouncementListCard({required this.item});

  final AnnouncementListItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnnouncementDetailPage(text: item.content),
          ),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.campaign_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.dateText,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.outline,
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
