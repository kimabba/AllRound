import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 경로는 profile_records_widgets.dart 의 import 를 그대로 따른다(실측 확인).
//   AppCard/AppCardVariant → widgets/app_card.dart
//   AppSpacing             → theme/tokens.dart
//   SectionHeader          → profile/profile_settings_widgets.dart
import '../../models/org_ranking.dart';
import '../../models/player_result.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart'; // divisionLabel, tennisOrgShortLabel
import '../app_card.dart';
import 'profile_settings_widgets.dart';

/// 프로필의 "내 기록" 섹션.
///
/// 연결 승인 전에는 연결 유도를, 승인 후에는 협회 전적을 보여준다.
/// 순위 관련 블록(라이프베스트·추이)은 스냅샷이 쌓인 뒤 2단계에서 붙인다 —
/// 지금 빈 그래프를 그리지 않는다.
class MyRecordSection extends ConsumerWidget {
  const MyRecordSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(myConfirmedLinkProvider);
    final results = ref.watch(myPlayerResultsProvider);
    final rankings = ref.watch(myCurrentRankingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '내 기록'),
        const SizedBox(height: AppSpacing.md),
        link.when(
          loading: () => const _RecordSkeleton(),
          error: (_, __) => const _RecordMessage('기록을 불러오지 못했습니다.'),
          data: (l) => l == null
              ? const _ConnectPrompt()
              : results.when(
                  loading: () => const _RecordSkeleton(),
                  error: (_, __) => const _RecordMessage('기록을 불러오지 못했습니다.'),
                  // 순위 조회가 실패해도 전적은 보여준다 — 둘은 독립적이다.
                  data: (rows) => RecordContent(
                    results: rows,
                    rankings: rankings.value ?? const [],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 연결 전 — 여기서 막히면 기능 전체가 죽는다. 무엇을 얻는지 먼저 말한다.
class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('협회 기록을 가져오세요', style: tt.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '협회 랭킹에서 본인을 확인하면 지금까지의 대회 전적이 채워집니다.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => context.push('/rankings'),
              child: const Text('협회 랭킹에서 찾기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 연결 후 본문. 상태를 안 들고 있어 위젯 테스트가 이것만 검증한다.
class RecordContent extends StatelessWidget {
  const RecordContent({
    super.key,
    required this.results,
    this.rankings = const [],
  });

  final List<PlayerResult> results;
  final List<OrgRankingRow> rankings;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // 블록 1 "지금" — 현재 순위. 전적이 없어도 이건 보여준다(연결만 되면 나온다).
    //
    // org_player_links.confirmed 는 (org_code, user_id) 별로 각각 있을 수 있어
    // 한 유저가 광주·전남 두 협회에 동시에 연결되기도 한다. myConfirmedLink() 는
    // 그중 하나만 돌려주므로 여기 보이는 순위는 "그 협회 한정"이다 — 카드마다
    // 협회 라벨을 붙여 화면이 전체인 척하지 않게 한다.
    final nowBlock = rankings.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...rankings.map((r) => AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tennisOrgShortLabel(r.orgCode)} · ${divisionLabel(r.divisionCode)}',
                          style: tt.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${r.rank}위', style: tt.titleMedium),
                        Text('${r.totalPoints}점', style: tt.bodyLarge),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.md),
            ],
          );

    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nowBlock,
          const _RecordMessage('아직 협회에 등록된 전적이 없습니다.'),
        ],
      );
    }

    final best = results.reduce((a, b) => b.points > a.points ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nowBlock,
        AppCard(
          key: const Key('best-moment-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('최고의 순간', style: tt.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text('${best.tournamentName} ${best.resultLabel}', style: tt.titleMedium),
              Text('+${best.points}점', style: tt.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('전적 ${results.length}건', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        ...results.map((r) => _ResultTile(result: r)),
        const SizedBox(height: AppSpacing.sm),
        Text('협회 공표 기준입니다. 앱이 계산한 점수가 아닙니다.', style: tt.bodySmall),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final PlayerResult result;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = result.playedOn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.tournamentName, style: tt.bodyLarge),
                Text(
                  '${d.year}.${d.month}.${d.day}'
                  '${result.eventRaw == null ? '' : ' · ${result.eventRaw}'}',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
          // 정규화 실패 행은 resultLabel 이 협회 원문을 그대로 돌려준다(예: '예선탈락').
          // 짧은 라벨('우승'·'16강')과 달리 길이가 예측 안 되므로 Flexible 로 감싼다 —
          // 원문은 자르지 않고 넘치지 않게만 만든다.
          Flexible(
            child: Text(
              result.resultLabel,
              style: tt.bodyLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('+${result.points}', style: tt.bodyLarge),
        ],
      ),
    );
  }
}

class _RecordMessage extends StatelessWidget {
  const _RecordMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        variant: AppCardVariant.outlined,
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _RecordSkeleton extends StatelessWidget {
  const _RecordSkeleton();

  @override
  Widget build(BuildContext context) => const AppCard(
        variant: AppCardVariant.outlined,
        child: SizedBox(height: 96),
      );
}
