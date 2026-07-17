import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../state/providers.dart';

/// 정형화 대기(needs_review + format_staged) 큐. 위젯 테스트에서 override 가능하도록
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
    final staged = (row['format_staged'] as Map?)?.cast<String, dynamic>() ?? {};
    final fields = (staged['regulation_fields'] as List?) ?? [];
    final sourceUrl = row['source_url'] as String?;
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
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await ref.read(apiProvider).applyStaged(row['id'] as String);
                    ref.invalidate(formatReviewQueueProvider);
                  },
                  child: const Text('승인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
