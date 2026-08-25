import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/profile/my_record_widgets.dart';

/// 랭킹 탭에서 진입하는 "내 기록" 전체 화면. MY(설정)에서 분리됐다 —
/// 기록은 콘텐츠지 설정이 아니다(2026-08-10 결정, 설계 문서 §2).
///
/// [orgCode] 가 있으면 그 협회 기준으로만 연결·전적·순위를 본다 — 랭킹 화면의
/// "내 기록 요약" 카드가 지금 보는 협회를 실어 보낸다(예: 전남협회 카드를
/// 탭했는데 광주 기록이 뜨는 불일치 방지). 없으면(알림 등 다른 진입) 기존
/// 동작 그대로 정렬 1순위 협회를 본다 — 하위호환.
class MyRecordScreen extends ConsumerWidget {
  const MyRecordScreen({super.key, this.orgCode});

  final String? orgCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = orgCode;
    return Scaffold(
      appBar: AppBar(title: const Text('내 기록')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: org == null
            ? _buildDefaultBody(ref)
            : _buildOrgBody(ref, org),
      ),
    );
  }

  Widget _buildDefaultBody(WidgetRef ref) {
    final link = ref.watch(myConfirmedLinkProvider);
    final results = ref.watch(myPlayerResultsProvider);
    final rankings = ref.watch(myCurrentRankingsProvider);
    final snapshots = ref.watch(myRankingHistoryProvider);

    return link.when(
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
    );
  }

  Widget _buildOrgBody(WidgetRef ref, String org) {
    final record = ref.watch(myRecordForOrgProvider(org));
    return record.when(
      loading: () => const RecordSkeleton(),
      error: (_, __) => const RecordMessage('기록을 불러오지 못했습니다.'),
      data: (r) => r.link == null
          ? const ConnectPrompt()
          : RecordContent(
              results: r.results,
              rankings: r.rankings,
              snapshots: r.snapshots,
            ),
    );
  }
}
