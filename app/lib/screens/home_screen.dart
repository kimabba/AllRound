// ignore_for_file: unused_element, unused_element_parameter

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/chat_entry_context.dart';
import '../models/rule_quiz.dart';
import '../models/tournament.dart';
import '../models/tournament_card_info.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../utils/kst.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/chat_sheet.dart';
import '../widgets/notification_inbox_action.dart';
import '../widgets/rule_quiz_dialog.dart';
import '../widgets/sport_title.dart';
import '../widgets/tournament_cover_image.dart';
import '../widgets/tournament_section_bar.dart';

enum _HomeTournamentFilter { recommended, thisWeek, all }

/// 홈에서 한 번에 보여주는 대회 수. 풋살과 테니스에 같은 기준을 적용한다.
const int homeTournamentDisplayLimit = 3;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _refresh() async {
    ref.invalidate(homeTournamentsProvider);
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(myClubsProvider);
    ref.invalidate(myCurrentRankingsProvider);
    ref.invalidate(unreadNotificationCountProvider);
    // 풋살 등급 카드 — 첫 조회가 실패해 카드가 "—"로 멈춰 있어도 당겨서
    // 새로고침하면 다시 시도할 수 있어야 한다.
    ref.invalidate(userSportsProvider);
    ref.invalidate(myFutsalAttendanceCountThisYearProvider);
    await ref.read(homeTournamentsProvider.future);
  }

  /// 홈은 전국 기준으로 다가오는 대회를 보여준다. 지역별 조회는 전체보기
  /// (전체 대회 화면)의 상세검색이 담당한다 — 홈의 지역 드롭다운은 검색창과
  /// 함께 그쪽으로 일원화하며 뺐다.
  List<Tournament> _visibleTournaments(
    List<Tournament> source,
    String selectedSport,
  ) {
    final sorted = [...source]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final today = kstTodayDate(DateTime.now());
    final upcoming = sorted
        .where(
          (item) =>
              item.sport == selectedSport &&
              !item.startDate.isBefore(today) &&
              !item.isRegistrationClosed,
        )
        .toList(growable: false);
    return upcoming;
  }

  Future<void> _toggleFavorite(Tournament tournament, bool saved) async {
    if (!AppConfig.userDesignPreview) {
      await ref.read(apiProvider).toggleFavorite(tournament.id, !saved);
    }
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(myTournamentRecordsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(homeTournamentsProvider);
    final myTournaments = ref.watch(myTournamentRecordsProvider);
    final cs = Theme.of(context).colorScheme;
    final selectedSport = ref.watch(activeSportProvider) ?? 'futsal';
    final favoriteIds =
        ref.watch(favoriteIdsProvider).value ?? const <String>{};
    final source = AppConfig.userDesignPreview
        ? AsyncValue.data(_previewTournaments())
        : tournaments;
    // 협회 연결이 없으면 null 이고 카드 자체가 뜨지 않는다. 풋살은 랭킹 미러가
    // 없어 이 카드가 말할 게 없으므로, 종목을 풋살로 바꾸면 테니스 랭킹이
    // 남아 있어도 감춘다.
    final gradeSummary = selectedSport == 'tennis'
        ? ref.watch(myGradeSummaryProvider).value
        : null;
    // 풋살은 협회 랭킹이 없어 본인이 설정한 등급(user_sports)을 보여준다 —
    // 테니스 카드와 다른 데이터 출처이므로 별도 위젯(_FutsalGradeCard)이다.
    final futsalUserSport = selectedSport == 'futsal'
        ? (ref.watch(userSportsProvider).value ?? const [])
            .where((s) => s.sport == 'futsal')
            .firstOrNull
        : null;

    return Scaffold(
      key: AllRoundE2EKeys.homeScreen,
      appBar: AppBar(
        // 종목을 타이틀로 올려 "지금 무엇을 보고 있는지"를 항상 보이게 하고,
        // 타이틀 자체가 종목 전환 버튼을 겸한다.
        title: const SportTitle(),
        titleSpacing: AppSpacing.xl,
        bottom: TournamentSectionBar(
          selected: TournamentSection.overview,
          showRankings: selectedSport == 'tennis',
        ),
        actions: [
          const NotificationInboxAction(),
          const ProfileAction(),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: cs.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (gradeSummary != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle(title: '내 랭킹'),
                      const SizedBox(height: AppSpacing.sm),
                      _MyGradeCard(
                        summary: gradeSummary,
                        onOpenRankings: () => context.push('/rankings'),
                        onAsk: () => openChatSheet(
                          context,
                          const ChatEntryContext(
                            screenLabel: '홈',
                            initialMessage: '협회마다 부서와 포인트 기준이 어떻게 다른가요?',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (futsalUserSport != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle(title: '내 등급'),
                      const SizedBox(height: AppSpacing.sm),
                      _FutsalGradeCard(
                        grade: futsalUserSport.grade,
                        clubCount: ref.watch(myClubsProvider).value?.length,
                        attendCount: ref
                            .watch(myFutsalAttendanceCountThisYearProvider)
                            .value,
                        onEditGrade: () => context.push('/profile'),
                      ),
                    ],
                  ),
                ),
              ),
            source.when(
              loading: () => const _HomeTournamentSkeleton(
                key: AllRoundE2EKeys.homeLoadingState,
              ),
              error: (_, __) => SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.xl),
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
                final visible = _visibleTournaments(items, selectedSport);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _TournamentHomeContent(
                      key: AllRoundE2EKeys.homeTournamentList,
                      tournaments: visible,
                      favorites: myTournaments.value
                              ?.where((item) => item.sport == selectedSport)
                              .toList() ??
                          const [],
                      favoriteIds: favoriteIds,
                      selectedSport: selectedSport,
                      onOpen: (item) => context.push('/tournaments/${item.id}'),
                      onFavorite: _toggleFavorite,
                      onBrowse: () => context.push('/tournaments'),
                      onRuleCategory: (category) => context.push(
                        Uri(
                          path: '/rules',
                          queryParameters: {
                            'sport': selectedSport,
                            'category': category,
                          },
                        ).toString(),
                      ),
                    ),
                  ),
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

/// 홈 최상단 "내 등급 카드"(풋살). 테니스 카드와 자리는 같지만 데이터 출처가
/// 다르다 — 협회 랭킹 미러가 없어 사용자가 프로필에서 직접 고른 등급
/// (user_sports)을 보여준다. 그래서 "내 랭킹"이 아니라 자기신고임을 알 수
/// 있게 "내가 설정한 등급"이라 쓰고, 카드 배경도 테니스 카드의 tint 카드가
/// 아니라 평면(no-card) 스타일로 둔다 — 협회가 보증한 값이 아니므로 같은
/// 무게로 보이면 안 된다.
class _FutsalGradeCard extends StatelessWidget {
  const _FutsalGradeCard({
    required this.grade,
    required this.clubCount,
    required this.attendCount,
    required this.onEditGrade,
  });

  final String grade;
  final int? clubCount;
  final int? attendCount;
  final VoidCallback onEditGrade;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;

    Widget stat(String label, String value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Icon(
                Icons.sports_soccer_rounded,
                size: 26,
                color: cs.onPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gradeLabel(grade),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Row 대신 Wrap — 200% 글자 크기에서 캡션이 넓어져도
                  // 옆으로 밀려나가지 않고 다음 줄로 접힌다.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '내가 설정한 등급 · ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      GestureDetector(
                        onTap: onEditGrade,
                        child: Text(
                          '수정',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 22),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              stat('가입한 클럽', clubCount?.toString() ?? '—'),
              Container(width: 1, height: 36, color: cs.outlineVariant),
              stat('이번 시즌 참가', attendCount == null ? '—' : '$attendCount회'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 홈 최상단 "내 등급 카드". 협회 랭킹에 본인 연결이 확정된 사용자에게만 뜬다.
///
/// 여기 나오는 부서·순위·점수는 전부 협회가 공표한 값이다 — 앱이 등급이나
/// 점수를 계산하지 않는다. 그래서 맨 아래에 "협회마다 기준이 다르다"는 안내를
/// 붙이고, 그 줄이 볼보이(챗봇) 입구를 겸한다.
class _MyGradeCard extends StatelessWidget {
  const _MyGradeCard({
    required this.summary,
    required this.onOpenRankings,
    required this.onAsk,
  });

  final MyGradeSummary summary;
  final VoidCallback onOpenRankings;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ranking = summary.ranking;
    final onTint = cs.onPrimaryContainer;
    // 라벨은 배경(primaryContainer) 위에서 본문보다 한 단계 물러나야 한다.
    final muted = onTint.withValues(alpha: 0.7);
    // 선·트랙처럼 읽히면 안 되는 요소는 더 얇게(시안 12%).
    final hairline = onTint.withValues(alpha: 0.12);
    final number = NumberFormat('#,###');
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;

    // 부서 이름은 3자('일반부')부터 6자('여자우승자부')까지 온다. 48px 원 안에
    // 고정 크기로 넣으면 긴 부서가 잘리므로 넘칠 때만 줄인다.
    final badge = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          divisionLabel(ranking.divisionCode),
          maxLines: 1,
          style: tt.labelMedium?.copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );

    final rank = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${tennisOrgShortLabel(ranking.orgCode)} 기준',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '랭킹 ${ranking.rank}위',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleLarge?.copyWith(
            color: onTint,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );

    final points = Column(
      crossAxisAlignment:
          largeText ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          '시즌 포인트',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${number.format(ranking.totalPoints)}P',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleLarge?.copyWith(
            color: onTint,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );

    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenRankings,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 큰 글씨에서는 한 줄에 순위와 포인트가 같이 못 들어간다.
              Row(
                children: [
                  badge,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: rank),
                  if (!largeText) ...[
                    const SizedBox(width: AppSpacing.sm),
                    points,
                  ],
                  Icon(Icons.chevron_right_rounded, size: 22, color: onTint),
                ],
              ),
              if (largeText) ...[const SizedBox(height: AppSpacing.md), points],
              const SizedBox(height: AppSpacing.md),
              _Top10Progress(
                rank: ranking.rank,
                myPoints: ranking.totalPoints,
                top10Points: summary.top10Points,
                trackColor: hairline,
              ),
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.md),
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: hairline)),
                ),
                child: Semantics(
                  button: true,
                  label: '볼보이에게 부서·포인트 기준 물어보기',
                  child: InkWell(
                    onTap: onAsk,
                    borderRadius: AppRadius.card,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.chat_bubble_rounded,
                          size: 15,
                          color: cs.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: '협회마다 부서·포인트 기준이 달라요. 궁금하면 ',
                              children: [
                                TextSpan(
                                  text: '볼보이',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                                const TextSpan(text: '에게 물어보세요'),
                              ],
                            ),
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
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

/// TOP 10 까지 남은 포인트 막대 + 그 아래 안내 한 줄.
///
/// 10위 점수를 모르면(그 부서에 10명이 안 되거나 조회 실패) 막대와 남은 점수를
/// 통째로 뺀다 — 0% 막대는 "꼴찌"로 읽힌다. 승급 안내는 그때도 남는다.
class _Top10Progress extends StatelessWidget {
  const _Top10Progress({
    required this.rank,
    required this.myPoints,
    required this.top10Points,
    required this.trackColor,
  });

  final int rank;
  final int myPoints;
  final int? top10Points;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final cutoff = top10Points;
    final inTop10 = rank <= 10;
    final hasBar = inTop10 || cutoff != null;

    // 순위는 협회가 매기고 점수는 표시용이라 둘이 어긋날 수 있다(같은 점수,
    // 다른 순위). 남은 점수가 음수로 보이지 않게 0 에서 자른다.
    final remaining =
        inTop10 || cutoff == null ? 0 : (cutoff - myPoints).clamp(0, cutoff);
    final progress = inTop10 || cutoff == null || cutoff == 0
        ? 1.0
        : (myPoints / cutoff).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasBar) ...[
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: cs.primary,
              backgroundColor: trackColor,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
        ],
        // 큰 글씨에서 두 문구가 한 줄에 못 들어가면 각자 줄을 차지한다.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: 2,
          children: [
            if (hasBar)
              Text(
                inTop10
                    ? 'TOP 10 안에 있어요'
                    : 'TOP 10까지 ${NumberFormat('#,###').format(remaining)}P',
                style: tt.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            Text(
              '승급은 입상 실적으로 결정돼요',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _TournamentHomeContent extends StatelessWidget {
  const _TournamentHomeContent({
    super.key,
    required this.tournaments,
    required this.favorites,
    required this.favoriteIds,
    required this.selectedSport,
    required this.onOpen,
    required this.onFavorite,
    required this.onBrowse,
    required this.onRuleCategory,
  });

  final List<Tournament> tournaments;
  final List<Tournament> favorites;
  final Set<String> favoriteIds;
  final String selectedSport;
  final ValueChanged<Tournament> onOpen;
  final Future<void> Function(Tournament, bool) onFavorite;
  final VoidCallback onBrowse;
  final ValueChanged<String> onRuleCategory;

  @override
  Widget build(BuildContext context) {
    final deadlineSoon = tournaments.where((item) {
      final deadline = item.applicationDeadline;
      if (deadline == null) return false;
      final today = kstTodayDate(DateTime.now());
      final days = deadline.difference(today).inDays;
      return days >= 0 && days <= 7;
    }).toList()
      ..sort(
        (a, b) => a.applicationDeadline!.compareTo(b.applicationDeadline!),
      );

    // 히어로는 "지금 신청해야 하는 것"을 맡는다. 마감 임박이 없을 때만
    // 다가오는 순서로 채운다.
    final heroItems =
        (deadlineSoon.isNotEmpty ? deadlineSoon : tournaments).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heroItems.isNotEmpty) ...[
          if (deadlineSoon.isNotEmpty) ...[
            const _SectionTitle(title: '접수 마감 임박'),
            const SizedBox(height: AppSpacing.sm),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: _TournamentHero(tournaments: heroItems, onOpen: onOpen),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        _InterestTournamentBand(
          tournaments: favorites,
          onOpen: onOpen,
          onBrowse: onBrowse,
        ),
        const SizedBox(height: AppSpacing.xxl),
        // 마감 임박 가로줄과 지역별 목록을 하나로 합쳤다. 예전에는 같은 대회가
        // 히어로·가로줄·목록에 최대 세 번 나왔다.
        _SectionTitle(title: '다가오는 대회', onAction: onBrowse),
        const SizedBox(height: AppSpacing.sm),
        if (tournaments.isEmpty)
          AppEmptyState(
            key: AllRoundE2EKeys.homeEmptyState,
            icon: Icons.calendar_month_outlined,
            title: '예정된 대회가 없습니다',
            description: '전체 대회에서 찾아보세요.',
            actionLabel: '전체 대회 보기',
            onAction: onBrowse,
          )
        else
          for (final item in tournaments.take(homeTournamentDisplayLimit))
            _TournamentListCard(
              tournament: item,
              saved: favoriteIds.contains(item.id),
              onOpen: () => onOpen(item),
              onFavorite: () => onFavorite(item, favoriteIds.contains(item.id)),
            ),
        const SizedBox(height: AppSpacing.xxl),
        _RulebookBand(sport: selectedSport, onCategory: onRuleCategory),
      ],
    );
  }
}

class _TournamentHero extends StatefulWidget {
  const _TournamentHero({required this.tournaments, required this.onOpen});

  final List<Tournament> tournaments;
  final ValueChanged<Tournament> onOpen;

  @override
  State<_TournamentHero> createState() => _TournamentHeroState();
}

class _TournamentHeroState extends State<_TournamentHero> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // 포스터가 한 장도 없으면(테니스 대부분) 사진 자리를 통째로 없애고
    // 카드 높이도 줄인다. 빈 색면이 첫 화면을 차지하지 않게 하기 위함.
    final hasPoster = widget.tournaments.any(
      (item) => (item.posterUrl ?? '').trim().isNotEmpty,
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final height = hasPoster ? 284.0 : (168.0 * scale).clamp(168.0, 284.0);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            itemCount: widget.tournaments.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final item = widget.tournaments[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index == widget.tournaments.length - 1 ? 0 : 6,
                ),
                child: _HeroTournamentCard(
                  tournament: item,
                  showImage: hasPoster,
                  onOpen: () => widget.onOpen(item),
                ),
              );
            },
          ),
        ),
        if (widget.tournaments.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < widget.tournaments.length; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == _page ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == _page
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: AppRadius.pill,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HeroTournamentCard extends StatelessWidget {
  const _HeroTournamentCard({
    required this.tournament,
    required this.onOpen,
    this.showImage = true,
  });

  final Tournament tournament;
  final VoidCallback onOpen;

  /// 사진 자리를 그릴지. 캐러셀 전체가 하나로 움직이도록 상위에서 정한다.
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deadline = applicationDeadlineText(
      tournament.applicationDeadline,
      DateFormat('M월 d일').format,
    );
    return Material(
      color: const Color(0xFF071B45),
      borderRadius: AppRadius.hero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showImage)
              Expanded(child: _TournamentImage(tournament: tournament))
            else
              const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 사진을 뺀 자리는 비워두지 않고 마감일로 채운다.
                        if (!showImage && deadline.isNotEmpty) ...[
                          Text(
                            deadline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Text(
                          tournament.title,
                          // 사진이 없으면 세로 여유가 생기므로 제목을 덜 자른다.
                          maxLines: showImage ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${DateFormat('M월 d일').format(tournament.startDate)} · ${tournament.location ?? tournament.region ?? '장소 미정'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilledButton(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      fixedSize: const Size(112, 44),
                      minimumSize: const Size(112, 44),
                    ),
                    child: const Text('대회 보기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestTournamentBand extends StatelessWidget {
  const _InterestTournamentBand({
    required this.tournaments,
    required this.onOpen,
    required this.onBrowse,
  });

  final List<Tournament> tournaments;
  final ValueChanged<Tournament> onOpen;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    if (tournaments.isEmpty) {
      return Material(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: onBrowse,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.favorite_border_rounded, color: cs.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '관심 대회가 없어요',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        '하트로 저장한 대회를 여기에 모아드려요',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onBrowse, child: const Text('대회 둘러보기')),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = largeText
            ? constraints.maxWidth * 0.84
            : tournaments.length > 2
                // 세 번째 카드의 일부를 보여 옆으로 더 있다는 것을 알린다.
                ? constraints.maxWidth * 0.54
                : (constraints.maxWidth - AppSpacing.sm) / 2;
        final cardHeight = cardWidth / 1.55 + 64;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: '관심 대회'),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tournaments.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) => SizedBox(
                  width: cardWidth,
                  child: _FavoriteTournamentCard(
                    tournament: tournaments[index],
                    onOpen: () => onOpen(tournaments[index]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FavoriteTournamentCard extends StatelessWidget {
  const _FavoriteTournamentCard({
    required this.tournament,
    required this.onOpen,
  });

  final Tournament tournament;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: AppRadius.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.55,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TournamentCoverImage(tournament: tournament),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          child: Icon(
                            Icons.favorite_rounded,
                            color: cs.primary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${DateFormat('M월 d일').format(tournament.startDate)} · ${tournament.region ?? '지역 미정'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
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

class _TournamentListCard extends StatelessWidget {
  const _TournamentListCard({
    required this.tournament,
    required this.saved,
    required this.onOpen,
    required this.onFavorite,
  });

  final Tournament tournament;
  final bool saved;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  /// 배지에 넣을 지역 한 단어. 여러 지역 공동개최는 첫 지역만, 지역이 없는
  /// 대회(전국대회)는 '전국'으로 읽는다.
  String get _regionBadge {
    // 빈 조각(선행 구분자 등)은 건너뛴다.
    final region = (tournament.region ?? '')
        .split('·')
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
    return region.isEmpty ? '전국' : region;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final organizer = (tournament.organizer ?? '').trim();
    final court = (tournament.location ?? '').trim();
    final date = DateFormat('M월 d일 (E)', 'ko').format(tournament.startDate);
    // 코트가 비면 가운뎃점만 덩그러니 남지 않게 날짜만 남긴다.
    final meta = [if (court.isNotEmpty) court, date].join(' · ');
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              // 포스터 썸네일을 뺀 자리. 대회 대부분이 포스터가 없어 같은 색면이
              // 반복됐고, 그 자리에 목록에서 실제로 훑는 값(지역)을 넣는다.
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _regionBadge,
                    maxLines: 1,
                    style: tt.titleMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (organizer.isNotEmpty) ...[
                      Text(
                        organizer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      tournament.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tournament.applicationDeadline == null
                          ? '접수 중'
                          : '~${DateFormat('M/d').format(tournament.applicationDeadline!)} 접수',
                      style: tt.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: saved ? '관심 해제' : '관심 대회 저장',
                onPressed: onFavorite,
                icon: Icon(
                  saved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: saved ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentImage extends StatelessWidget {
  const _TournamentImage({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    return TournamentCoverImage(tournament: tournament);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.onAction});

  final String title;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        if (onAction != null)
          TextButton(onPressed: onAction, child: const Text('전체보기')),
      ],
    );
  }
}

class _RulebookBand extends StatelessWidget {
  const _RulebookBand({required this.sport, required this.onCategory});

  final String sport;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = sport == 'tennis' ? '테니스 룰북' : '풋살 룰북';
    final quiz = dailyRuleQuiz(sport);
    final categories = sport == 'tennis'
        ? const [
            (icon: Icons.sports_rounded, label: '경기 진행'),
            (icon: Icons.sports_tennis_rounded, label: '서브'),
            (icon: Icons.swipe_up_rounded, label: '발리'),
            (icon: Icons.groups_2_outlined, label: '복식/라인'),
          ]
        : const [
            (icon: Icons.sports_rounded, label: '경기 진행'),
            (icon: Icons.sports_handball_rounded, label: '골키퍼'),
            (icon: Icons.warning_amber_rounded, label: '파울'),
            (icon: Icons.replay_rounded, label: '킥인/재개'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: cs.primary,
            borderRadius: AppRadius.hero,
            child: Semantics(
              button: true,
              label: '오늘의 핵심 퀴즈 풀기',
              child: InkWell(
                onTap: () => showRuleQuizDialog(context, quiz),
                borderRadius: AppRadius.hero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '오늘의 핵심 퀴즈',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: cs.onPrimary.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        quiz.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: cs.onPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '배너를 눌러 문제를 풀어보세요',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onPrimary.withValues(alpha: 0.82),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var index = 0; index < categories.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _RuleItem(
                  categories[index].icon,
                  categories[index].label,
                  onTap: () => onCategory(categories[index].label),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.icon, this.label, {required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: AppRadius.card,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 76;
              final labelWidget = Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              );
              if (compact) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: cs.primary, size: 16),
                    const SizedBox(height: 2),
                    labelWidget,
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: cs.primary, size: 17),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(child: labelWidget),
                ],
              );
            },
          ),
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
            Text(
              date,
              style: tt.labelMedium?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '오늘,\n어디서 뛸까요?',
              style: tt.displayMedium?.copyWith(color: cs.onPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '신청 가능한 대회와 클럽 모임을 빠르게 확인하세요.',
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
    final today = kstTodayDate(DateTime.now());
    final upcoming = tournaments
        .where((item) => !item.startDate.isBefore(today))
        .toList(growable: false)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final tournament = upcoming.firstOrNull;
    final club = clubs.where((item) => item.isMember).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HomeSectionHeader(title: '내 활동'),
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
                label: '가입한 클럽',
                title: club?.name ?? '가입 클럽 없음',
                status: club == null
                    ? '클럽을 찾아보세요'
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
    this.onAction,
    this.actionKey,
  });

  final String title;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final row = Row(
      children: [
        Expanded(child: Text(title, style: tt.titleLarge)),
        if (onAction != null)
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ],
    );
    if (onAction == null) return row;
    return InkWell(
      key: actionKey,
      onTap: onAction,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
        child: Align(alignment: Alignment.centerLeft, child: row),
      ),
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
              label: '전체',
              selected: selected == _HomeTournamentFilter.all,
              onTap: () => onSelected(_HomeTournamentFilter.all),
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
              label: '추천',
              selected: selected == _HomeTournamentFilter.recommended,
              onTap: () => onSelected(_HomeTournamentFilter.recommended),
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
    final today = kstTodayDate(DateTime.now());
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
  // device-local-ok: 화면 프리뷰용 더미 대회를 만든다 — 마감 판정이 아니다.
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
