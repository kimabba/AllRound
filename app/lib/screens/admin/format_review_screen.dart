import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../state/providers.dart';

/// 정형화 검수 대기(needs_review) 큐. staged 콘텐츠가 있는 행과 검증 실패로
/// format_flags 만 있는 행을 모두 포함한다. 위젯 테스트에서 override 가능하도록
/// public 으로 노출.
final formatReviewQueueProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(apiProvider).formatReviewQueue();
});

class FormatReviewScreen extends ConsumerWidget {
  const FormatReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(formatReviewQueueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('요강 검수')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('검수할 요강이 없습니다.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ReviewCard(row: rows[i]),
              ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stagedRaw = row['format_staged'] as Map?;
    final sourceUrl = row['source_url'] as String?;
    final hasStaged = stagedRaw != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row['title'] as String? ?? '',
                style: Theme.of(context).textTheme.titleMedium),
            if (sourceUrl != null)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('원문 공고 보기'),
                onPressed: () => launchUrl(Uri.parse(sourceUrl)),
              ),
            const SizedBox(height: 8),
            if (hasStaged)
              ..._stagedContent(context, stagedRaw.cast<String, dynamic>())
            else
              ..._validationFailureContent(context),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(apiProvider)
                        .rejectStaged(row['id'] as String, '검수 반려');
                    ref.invalidate(formatReviewQueueProvider);
                  },
                  child: const Text('반려'),
                ),
                if (hasStaged) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 44),
                    ),
                    onPressed: () async {
                      await ref
                          .read(apiProvider)
                          .applyStaged(row['id'] as String);
                      ref.invalidate(formatReviewQueueProvider);
                    },
                    child: const Text('승인'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stagedContent(BuildContext context, Map<String, dynamic> staged) {
    final fields = (staged['regulation_fields'] as List?) ?? [];
    return [
      ...fields.map((f) {
        final m = (f as Map).cast<String, dynamic>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${m['label']}: ${m['value']}'),
        );
      }),
      if (staged['description'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('요약: ${staged['description']}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
    ];
  }

  List<Widget> _validationFailureContent(BuildContext context) {
    final flags = (row['format_flags'] as List?) ?? [];
    return [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '검증 실패 — 자동 반영 불가, 수동 확인 필요',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            ...flags.map((f) {
              final m = (f as Map).cast<String, dynamic>();
              final field = m['field'];
              final code = m['code'];
              final masked = m['masked'];
              final maskedSuffix =
                  (masked != null && (masked as String).isNotEmpty)
                      ? ' ($masked)'
                      : '';
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '검증 실패: $field — $code$maskedSuffix',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                ),
              );
            }),
          ],
        ),
      ),
    ];
  }
}
