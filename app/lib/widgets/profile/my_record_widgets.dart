import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/org_ranking.dart';
import '../../models/org_ranking_snapshot.dart';
import '../../models/player_result.dart';
import '../../models/season_stats.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart'; // divisionLabel, tennisOrgShortLabel
import '../app_card.dart';
import '../rankings/rank_trend_sparkline.dart';

/// 연결 전 — 여기서 막히면 기능 전체가 죽는다. 무엇을 얻는지 먼저 말한다.
class ConnectPrompt extends StatelessWidget {
  const ConnectPrompt({super.key});

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

/// 연결 후 본문(그리고 다른 선수 상세시트에서도 재사용). 상태를 안 들고
/// 있어 위젯 테스트가 이것만 검증한다.
class RecordContent extends StatelessWidget {
  const RecordContent({
    super.key,
    required this.results,
    this.rankings = const [],
    this.snapshots = const [],
  });

  final List<PlayerResult> results;
  final List<OrgRankingRow> rankings;
  final List<OrgRankingSnapshot> snapshots;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // 블록 1 "지금" — 현재 순위. 전적이 없어도 이건 보여준다(연결만 되면 나온다).
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

    // 순위 추이는 전적(results)과 독립이다 — 스냅샷은 연결 여부와 무관하게
    // 전 선수가 매일 자동 적재된다. 전적이 없는 선수도 그래프는 볼 수 있다.
    final trendBlock = snapshots.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RankTrendSparkline(snapshots: snapshots),
              const SizedBox(height: AppSpacing.md),
            ],
          );

    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nowBlock,
          trendBlock,
          const RecordMessage('아직 협회에 등록된 전적이 없습니다.'),
        ],
      );
    }

    final best = results.reduce((a, b) => b.points > a.points ? b : a);
    final seasonStats = SeasonStats.compute(
      results: results,
      snapshots: snapshots,
      currentYear: DateTime.now().year,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nowBlock,
        _SeasonStatsBlock(stats: seasonStats),
        const SizedBox(height: AppSpacing.md),
        trendBlock,
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

class _SeasonStatsBlock extends StatelessWidget {
  const _SeasonStatsBlock({required this.stats});

  final SeasonStats stats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final distributionEntries = stats.resultDistribution.entries.toList()
      ..sort((a, b) {
        if (a.key == null) return 1;
        if (b.key == null) return -1;
        return a.key!.compareTo(b.key!);
      });

    return AppCard(
      key: const Key('season-stats-card'),
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 시즌 기록', style: tt.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _StatItem(label: '올해 참가', value: '${stats.tournamentsThisYear}개 대회'),
              _StatItem(label: '누적 우승', value: '${stats.careerWins}회'),
              if (stats.allTimeBestRank != null)
                _StatItem(label: '역대 최고', value: '${stats.allTimeBestRank}위'),
            ],
          ),
          if (distributionEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final e in distributionEntries)
                  Chip(
                    label: Text('${seasonDistributionLabel(e.key)} ${e.value}'),
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value, style: tt.titleMedium),
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
          Flexible(
            child: Text(result.resultLabel, style: tt.bodyLarge),
          ),
          const SizedBox(width: AppSpacing.md),
          Text('+${result.points}', style: tt.bodyLarge),
        ],
      ),
    );
  }
}

class RecordMessage extends StatelessWidget {
  const RecordMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        variant: AppCardVariant.outlined,
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class RecordSkeleton extends StatelessWidget {
  const RecordSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const AppCard(
        variant: AppCardVariant.outlined,
        child: SizedBox(height: 96),
      );
}
