import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/profile/my_record_widgets.dart';

/// 랭킹 탭에서 진입하는 "내 기록" 전체 화면. MY(설정)에서 분리됐다 —
/// 기록은 콘텐츠지 설정이 아니다(2026-08-10 결정, 설계 문서 §2).
class MyRecordScreen extends ConsumerWidget {
  const MyRecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(myConfirmedLinkProvider);
    final results = ref.watch(myPlayerResultsProvider);
    final rankings = ref.watch(myCurrentRankingsProvider);
    final snapshots = ref.watch(myRankingHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 기록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: link.when(
          loading: () => const RecordSkeleton(),
          error: (_, __) => const RecordMessage('기록을 불러오지 못했습니다.'),
          data: (l) => l == null
              ? const ConnectPrompt()
              : results.when(
                  loading: () => const RecordSkeleton(),
                  error: (_, __) => const RecordMessage('기록을 불러오지 못했습니다.'),
                  data: (rows) => RecordContent(
                    results: rows,
                    rankings: rankings.value ?? const [],
                    snapshots: snapshots.value ?? const [],
                  ),
                ),
        ),
      ),
    );
  }
}
