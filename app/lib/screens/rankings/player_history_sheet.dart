import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/org_ranking.dart';
import '../../models/player_result.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

Future<void> showPlayerHistorySheet(
  BuildContext context, {
  required OrgRankingRow player,
  required Future<PlayerHistory> Function() load,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: PlayerHistorySheet(player: player, load: load),
    ),
  );
}

class PlayerHistorySheet extends StatefulWidget {
  const PlayerHistorySheet({
    super.key,
    required this.player,
    required this.load,
  });

  final OrgRankingRow player;
  final Future<PlayerHistory> Function() load;

  @override
  State<PlayerHistorySheet> createState() => _PlayerHistorySheetState();
}

class _PlayerHistorySheetState extends State<PlayerHistorySheet> {
  late Future<PlayerHistory> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _retry() {
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '선수 기록',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: FutureBuilder<PlayerHistory>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _HistoryLoading(player: widget.player);
              }
              if (snapshot.hasError) {
                return _HistoryError(player: widget.player, onRetry: _retry);
              }
              return _HistoryContent(
                player: widget.player,
                history: snapshot.data!,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlayerSummary extends StatelessWidget {
  const _PlayerSummary({required this.player, this.recordCount});

  final OrgRankingRow player;
  final int? recordCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final club = player.clubRaw?.replaceAll('/', '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(
                  minWidth: AppSizes.touchTarget,
                  minHeight: AppSizes.touchTarget,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: player.rank == 1 ? cs.primary : cs.primaryContainer,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  '${player.rank}위',
                  style: tt.titleMedium?.copyWith(
                    color:
                        player.rank == 1 ? cs.onPrimary : cs.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.playerName,
                      style: tt.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (club != null && club.isNotEmpty)
                      Text(
                        club,
                        style:
                            tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: [
              _SummaryFact(
                label: '부서',
                value: divisionLabel(player.divisionCode),
              ),
              _SummaryFact(
                label: '누적 포인트',
                value:
                    '${NumberFormat.decimalPattern('ko').format(player.totalPoints)}점',
              ),
              if (recordCount != null)
                _SummaryFact(label: '대회 이력', value: '$recordCount건'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryFact extends StatelessWidget {
  const _SummaryFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading({required this.player});

  final OrgRankingRow player;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        _PlayerSummary(player: player),
        const SizedBox(height: AppSpacing.xxxl),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: AppSpacing.md),
        const Center(child: Text('협회에서 선수 이력을 확인하고 있습니다')),
      ],
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.player, required this.onRetry});

  final OrgRankingRow player;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        _PlayerSummary(player: player),
        const SizedBox(height: AppSpacing.xxxl),
        Icon(Icons.cloud_off_rounded, size: 32, color: cs.onSurfaceVariant),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '선수 이력을 불러오지 못했습니다',
          textAlign: TextAlign.center,
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '협회 연결 상태를 확인한 뒤 다시 시도해 주세요.',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('다시 불러오기')),
        ),
      ],
    );
  }
}

class _HistoryContent extends StatelessWidget {
  const _HistoryContent({required this.player, required this.history});

  final OrgRankingRow player;
  final PlayerHistory history;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final results = [...history.results]
      ..sort((a, b) => b.playedOn.compareTo(a.playedOn));

    return ListView(
      key: const Key('player-history-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.huge,
      ),
      children: [
        _PlayerSummary(player: player, recordCount: results.length),
        const SizedBox(height: AppSpacing.xxxl),
        Text(
          '대회 이력',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (results.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Text(
              '협회에 등록된 대회 이력이 없습니다.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._buildYearGroups(context, results),
        if (!history.isComplete) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            '이력이 많아 최근 기록부터 표시했습니다.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        Text(
          '${DateFormat('yyyy.MM.dd').format(history.fetchedAt.toLocal())} 기준 · '
          '협회 공표 자료이며 앱이 계산한 결과가 아닙니다.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  List<Widget> _buildYearGroups(
    BuildContext context,
    List<PlayerResult> results,
  ) {
    final widgets = <Widget>[];
    int? currentYear;
    for (final result in results) {
      if (result.playedOn.year != currentYear) {
        currentYear = result.playedOn.year;
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: AppSpacing.lg));
        }
        widgets.add(_YearHeader(year: currentYear));
      }
      widgets.add(_PlayerResultRow(result: result));
    }
    return widgets;
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Text(
        '$year년',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _PlayerResultRow extends StatelessWidget {
  const _PlayerResultRow({required this.result});

  final PlayerResult result;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = DateFormat('MM.dd').format(result.playedOn);
    final points = NumberFormat.decimalPattern('ko').format(result.points);

    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.listRow),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              date,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.tournamentName,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (result.eventRaw != null && result.eventRaw!.isNotEmpty)
                  Text(
                    result.eventRaw!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.control * 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result.resultLabel,
                  textAlign: TextAlign.end,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '+$points점',
                  textAlign: TextAlign.end,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
