import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';
import 'profile_settings_widgets.dart';
import 'profile_sports_widgets.dart';

// ────────────────────────────────────────────────────────────
// 내가 등록한 클럽 섹션
// ────────────────────────────────────────────────────────────

class MyClubsSection extends ConsumerWidget {
  const MyClubsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final clubs = ref.watch(myClubsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '내가 등록한 클럽',
          action: SectionActionButton(
            label: '둘러보기',
            onTap: () => context.go('/clubs'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        clubs.when(
          loading: () =>
              const AppCard(child: Center(child: CircularProgressIndicator())),
          error: (_, __) => AppCard(
            child: Text(
              '등록 클럽을 불러오지 못했습니다.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          data: (items) => items.isEmpty
              ? AppCard(
                  variant: AppCardVariant.elevated,
                  borderRadius: BorderRadius.circular(16),
                  child: MyClubEmptyContent(cs: cs, tt: tt),
                )
              : Column(
                  children: [
                    for (final club in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          variant: AppCardVariant.elevated,
                          borderRadius: BorderRadius.circular(16),
                          child: Row(
                            children: [
                              ProfileSportThumbnail(sport: club.sport),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      club.name,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      [
                                        sportLabelFromString(club.sport),
                                        if (club.region != null) club.region!,
                                      ].join(' · '),
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class MyClubEmptyContent extends StatelessWidget {
  const MyClubEmptyContent({super.key, required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.groups_rounded,
            color: cs.onSecondaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '아직 등록한 클럽이 없습니다',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '마음에 드는 클럽을 찾아 등록하면 이곳에 표시됩니다.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 내 대회 기록 섹션
// ────────────────────────────────────────────────────────────

class MyTournamentRecordsSection extends ConsumerWidget {
  const MyTournamentRecordsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final records = ref.watch(myTournamentRecordsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '내 대회 기록',
          action: SectionActionButton(
            label: '대회 보기',
            onTap: () => context.go('/tournaments'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        records.when(
          loading: () => const TournamentRecordSkeleton(),
          error: (_, __) => !kReleaseMode
              ? TournamentRecordsList(
                  tournaments: previewTournamentRecords(),
                  preview: true,
                )
              : AppCard(
                  variant: AppCardVariant.elevated,
                  borderRadius: BorderRadius.circular(16),
                  child: Text(
                    '대회 기록을 불러오지 못했습니다.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
          data: (items) => items.isEmpty
              ? AppCard(
                  variant: AppCardVariant.elevated,
                  borderRadius: BorderRadius.circular(16),
                  child: TournamentRecordEmptyContent(cs: cs, tt: tt),
                )
              : TournamentRecordsList(tournaments: items),
        ),
      ],
    );
  }
}

class TournamentRecordsList extends StatelessWidget {
  const TournamentRecordsList({
    super.key,
    required this.tournaments,
    this.preview = false,
  });

  final List<Tournament> tournaments;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        if (preview) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  size: 18,
                  color: Color(0xFFEA580C),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '백엔드 연결 전 디자인 미리보기 기록입니다.',
                    style: tt.labelMedium?.copyWith(
                      color: const Color(0xFF9A3412),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SizedBox(
          height: 174,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tournaments.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final tournament = tournaments[index];
              final isTennis = tournament.sport == 'tennis';
              final accent = isTennis ? cs.tertiary : cs.secondary;
              return SizedBox(
                width: 270,
                child: AppCard(
                  onTap: preview
                      ? null
                      : () => context.push('/tournaments/${tournament.id}'),
                  variant: AppCardVariant.elevated,
                  borderRadius: BorderRadius.circular(16),
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage(
                                isTennis
                                    ? 'assets/images/tournaments/tennis-cover.jpg'
                                    : 'assets/images/tournaments/futsal-cover.jpg',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(
                                  color: Colors.black.withValues(alpha: 0.22),
                                ),
                              ),
                              Positioned(
                                left: AppSpacing.md,
                                bottom: AppSpacing.sm,
                                child: RecordBadge(
                                  icon: isTennis
                                      ? Icons.sports_tennis_rounded
                                      : Icons.sports_soccer_rounded,
                                  label: sportLabelFromString(tournament.sport),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: AppRadius.pill,
                                    ),
                                    child: Text(
                                      recordStatusLabel(tournament),
                                      style: tt.labelSmall?.copyWith(
                                        color: accent,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.bookmark_rounded,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                tournament.title,
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                [
                                  shortDate(tournament.startDate),
                                  tournament.region,
                                ].whereType<String>().join(' · '),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RecordBadge extends StatelessWidget {
  const RecordBadge({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF111827)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class TournamentRecordSkeleton extends StatelessWidget {
  const TournamentRecordSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      variant: AppCardVariant.elevated,
      child: SizedBox(
        height: 88,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class TournamentRecordEmptyContent extends StatelessWidget {
  const TournamentRecordEmptyContent({
    super.key,
    required this.cs,
    required this.tt,
  });

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.emoji_events_rounded,
            color: cs.onPrimaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '아직 저장한 대회가 없습니다',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '관심 대회를 저장하면 내 대회 기록에 표시됩니다.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// Helper functions
// ────────────────────────────────────────────────────────────

List<Tournament> previewTournamentRecords() {
  final now = DateTime.now();
  return [
    Tournament(
      id: 'preview-my-tennis',
      sport: 'tennis',
      title: '광주 오픈 테니스 챌린지',
      organizer: '광주테니스협회',
      description: 'MY 화면 디자인 미리보기용 대회입니다.',
      startDate: now.add(const Duration(days: 12)),
      applicationDeadline: now.add(const Duration(days: 5)),
      region: '광주',
      location: '염주실내테니스장',
      eligibleGrades: const ['under1y', 'y1to3'],
      entryFee: 40000,
      entryFeeUnit: 'per_person',
      status: 'published',
    ),
    Tournament(
      id: 'preview-my-futsal',
      sport: 'futsal',
      title: '서울 풋살 위클리 컵',
      organizer: '올라운드 풋살 커뮤니티',
      description: 'MY 화면 디자인 미리보기용 대회입니다.',
      startDate: now.add(const Duration(days: 9)),
      applicationDeadline: now.add(const Duration(days: 4)),
      region: '수도권',
      location: '서울 송파 풋살파크',
      eligibleGrades: const ['intro', 'beginner', 'intermediate'],
      entryFee: 80000,
      status: 'published',
      futsalEventCategory: 'private',
    ),
  ];
}

String recordStatusLabel(Tournament tournament) {
  final deadline = tournament.applicationDeadline;
  if (deadline == null) return '관심 대회';
  final today = DateTime.now();
  final daysLeft =
      deadline.difference(DateTime(today.year, today.month, today.day)).inDays;
  if (daysLeft < 0) return '마감';
  if (daysLeft == 0) return '오늘 마감';
  return 'D-$daysLeft';
}

String shortDate(DateTime date) => '${date.month}.${date.day}';
