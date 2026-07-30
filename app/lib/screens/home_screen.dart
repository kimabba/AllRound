import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/notification_inbox_action.dart';

enum _HomeTournamentFilter { recommended, thisWeek, all }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeTournamentFilter _filter = _HomeTournamentFilter.recommended;

  Future<void> _refresh() async {
    ref.invalidate(homeTournamentsProvider);
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(myClubsProvider);
    ref.invalidate(unreadNotificationCountProvider);
    await ref.read(homeTournamentsProvider.future);
  }

  List<Tournament> _visibleTournaments(List<Tournament> source) {
    final sorted = [...source]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = sorted
        .where((item) => !item.startDate.isBefore(today))
        .toList(growable: false);

    return switch (_filter) {
      _HomeTournamentFilter.recommended => upcoming.take(4).toList(),
      _HomeTournamentFilter.thisWeek => upcoming
          .where((item) => item.startDate.difference(today).inDays <= 7)
          .take(5)
          .toList(),
      _HomeTournamentFilter.all => upcoming.take(7).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(homeTournamentsProvider);
    final myTournaments = ref.watch(myTournamentRecordsProvider);
    final myClubs = ref.watch(myClubsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      key: AllRoundE2EKeys.homeScreen,
      appBar: AppBar(
        title: Text(
          '올라운드',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
        ),
        actions: [const NotificationInboxAction(), const SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        color: cs.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverToBoxAdapter(child: _HomeIntro()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _HomePersonalSchedule(
                  tournaments: myTournaments.value ?? const [],
                  clubs: myClubs.value ?? const [],
                  onTournamentBrowse: () => context.go('/tournaments'),
                  onClubBrowse: () => context.go('/clubs'),
                  onTournamentTap: (item) =>
                      context.push('/tournaments/${item.id}'),
                  onClubTap: (club) => context.push('/clubs/${club.id}'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxxl,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _HomeSectionHeader(
                  title: '다가오는 대회',
                  actionLabel: '전체 보기',
                  onAction: () => context.go('/tournaments'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverToBoxAdapter(
                child: _HomeFilterTabs(
                  selected: _filter,
                  onSelected: (value) => setState(() => _filter = value),
                ),
              ),
            ),
            if (AppConfig.userDesignPreview)
              _TournamentListSliver(
                tournaments: _visibleTournaments(_previewTournaments()),
                onTap: (item) => context.push('/tournaments/${item.id}'),
              )
            else
              tournaments.when(
                loading: () => const _HomeTournamentSkeleton(
                  key: AllRoundE2EKeys.homeLoadingState,
                ),
                error: (_, __) => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.huge,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppEmptyState(
                      key: AllRoundE2EKeys.homeErrorState,
                      icon: Icons.refresh_rounded,
                      title: '대회를 불러오지 못했습니다',
                      description: '연결 상태를 확인한 뒤 다시 시도해 주세요.',
                      actionLabel: '다시 불러오기',
                      onAction: () => ref.invalidate(homeTournamentsProvider),
                    ),
                  ),
                ),
                data: (items) {
                  final visible = _visibleTournaments(items);
                  if (visible.isEmpty) {
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.huge,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: AppEmptyState(
                          key: AllRoundE2EKeys.homeEmptyState,
                          icon: Icons.calendar_month_outlined,
                          title: '예정된 대회가 없습니다',
                          description: '필터를 바꾸거나 전체 대회에서 찾아보세요.',
                          actionLabel: '전체 대회 보기',
                          onAction: () => context.go('/tournaments'),
                        ),
                      ),
                    );
                  }
                  return _TournamentListSliver(
                    key: AllRoundE2EKeys.homeTournamentList,
                    tournaments: visible,
                    onTap: (item) => context.push('/tournaments/${item.id}'),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 112)),
          ],
        ),
      ),
    );
  }
}

class _HomeIntro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final date = DateFormat('M월 d일 EEEE', 'ko').format(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: AppRadius.hero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    date,
                    style: tt.labelMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.bolt_rounded,
                      size: 20,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '오늘,\n어디서 뛸까요?',
              style: tt.displayMedium?.copyWith(color: cs.onPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '신청 가능한 대회와 클럽 일정을 빠르게 확인하세요.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onPrimary.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePersonalSchedule extends StatelessWidget {
  const _HomePersonalSchedule({
    required this.tournaments,
    required this.clubs,
    required this.onTournamentBrowse,
    required this.onClubBrowse,
    required this.onTournamentTap,
    required this.onClubTap,
  });

  final List<Tournament> tournaments;
  final List<Club> clubs;
  final VoidCallback onTournamentBrowse;
  final VoidCallback onClubBrowse;
  final ValueChanged<Tournament> onTournamentTap;
  final ValueChanged<Club> onClubTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = tournaments
        .where((item) => !item.startDate.isBefore(today))
        .toList(growable: false)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final tournament = upcoming.firstOrNull;
    final club = clubs.where((item) => item.isMember).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSectionHeader(title: '나의 일정'),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PersonalScheduleCard(
                icon: Icons.emoji_events_outlined,
                color: cs.primaryContainer,
                label: '저장한 대회',
                title: tournament?.title ?? '예정 대회 없음',
                status: tournament == null
                    ? '대회를 둘러보세요'
                    : _dayLabel(tournament.startDate, today),
                onTap: tournament == null
                    ? onTournamentBrowse
                    : () => onTournamentTap(tournament),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PersonalScheduleCard(
                icon: Icons.groups_2_outlined,
                color: cs.surfaceContainerLow,
                label: '가입한 모임',
                title: club?.name ?? '가입 모임 없음',
                status: club == null
                    ? '모임을 찾아보세요'
                    : '${club.region ?? '지역 미정'} · ${club.memberCount}명',
                onTap: club == null ? onClubBrowse : () => onClubTap(club),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _dayLabel(DateTime date, DateTime today) {
    final target = DateTime(date.year, date.month, date.day);
    final days = target.difference(today).inDays;
    if (days == 0) return '오늘';
    return 'D-$days';
  }
}

class _PersonalScheduleCard extends StatelessWidget {
  const _PersonalScheduleCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.title,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String title;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      variant: AppCardVariant.outlined,
      backgroundColor: color,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(title, style: tt.titleLarge)),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _HomeFilterTabs extends StatelessWidget {
  const _HomeFilterTabs({required this.selected, required this.onSelected});

  final _HomeTournamentFilter selected;
  final ValueChanged<_HomeTournamentFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: AppSizes.touchTarget,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterTab(
              label: '추천',
              selected: selected == _HomeTournamentFilter.recommended,
              onTap: () => onSelected(_HomeTournamentFilter.recommended),
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: '이번 주',
              selected: selected == _HomeTournamentFilter.thisWeek,
              onTap: () => onSelected(_HomeTournamentFilter.thisWeek),
            ),
          ),
          Expanded(
            child: _FilterTab(
              label: '전체',
              selected: selected == _HomeTournamentFilter.all,
              onTap: () => onSelected(_HomeTournamentFilter.all),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.labelLarge?.copyWith(
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TournamentListSliver extends StatelessWidget {
  const _TournamentListSliver({
    super.key,
    required this.tournaments,
    required this.onTap,
  });

  final List<Tournament> tournaments;
  final ValueChanged<Tournament> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: AppCard(
          variant: AppCardVariant.outlined,
          child: Column(
            children: [
              for (var index = 0; index < tournaments.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                _HomeTournamentRow(
                  tournament: tournaments[index],
                  onTap: () => onTap(tournaments[index]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTournamentRow extends StatelessWidget {
  const _HomeTournamentRow({required this.tournament, required this.onTap});

  final Tournament tournament;
  final VoidCallback onTap;

  String _deadlineLabel() {
    final deadline = tournament.applicationDeadline;
    if (deadline == null) {
      return tournament.isRegistrationClosed ? '접수 마감' : '접수 중';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = deadline.difference(today).inDays;
    if (days < 0 || tournament.isRegistrationClosed) return '접수 마감';
    if (days == 0) return '오늘 마감';
    return '접수 마감 D-$days';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = tournament.startDate;
    final location = tournament.location ?? tournament.region ?? '장소 확인 중';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 98),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd').format(date),
                        style: tt.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${date.month}월', style: tt.labelSmall),
                    ],
                  ),
                ),
                Container(width: 1, height: 58, color: cs.outlineVariant),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tournament.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _deadlineLabel(),
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTournamentSkeleton extends StatelessWidget {
  const _HomeTournamentSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      sliver: SliverList.separated(
        itemCount: 3,
        separatorBuilder: (_, __) => Divider(color: cs.outlineVariant),
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            children: [
              Container(width: 52, height: 52, color: cs.surfaceContainerHigh),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      color: cs.surfaceContainerHigh,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: 150,
                      height: 11,
                      color: cs.surfaceContainerHigh,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Tournament> _previewTournaments() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return [
    Tournament(
      id: 'preview-home-seoul-open',
      sport: 'tennis',
      title: '서울 오픈 테니스',
      organizer: '서울테니스협회',
      startDate: today.add(const Duration(days: 7)),
      applicationDeadline: today.add(const Duration(days: 3)),
      region: '서울',
      location: '올림픽공원 테니스장',
      eligibleGrades: const ['open'],
      entryFee: 60000,
      status: 'published',
    ),
    Tournament(
      id: 'preview-home-ranking',
      sport: 'tennis',
      title: '전국 동호인 테니스대회',
      organizer: '대한테니스협회',
      startDate: today.add(const Duration(days: 15)),
      applicationDeadline: today.add(const Duration(days: 8)),
      region: '서울',
      location: '송파구 종합운동장',
      eligibleGrades: const ['open'],
      entryFee: 60000,
      status: 'published',
    ),
    Tournament(
      id: 'preview-home-futsal',
      sport: 'futsal',
      title: '서울 풋살 챔피언십',
      organizer: '서울풋살연맹',
      startDate: today.add(const Duration(days: 22)),
      applicationDeadline: today.add(const Duration(days: 12)),
      region: '서울',
      location: '마포 난지 풋살장',
      eligibleGrades: const ['open'],
      entryFee: 80000,
      status: 'published',
    ),
    Tournament(
      id: 'preview-home-night-cup',
      sport: 'tennis',
      title: '한강 나이트 테니스 컵',
      organizer: '한강테니스클럽',
      startDate: today.add(const Duration(days: 28)),
      applicationDeadline: today.add(const Duration(days: 18)),
      region: '서울',
      location: '망원 테니스장',
      eligibleGrades: const ['open'],
      entryFee: 40000,
      status: 'published',
    ),
  ];
}
