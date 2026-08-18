// ignore_for_file: unused_element, unused_element_parameter

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../models/tournament_card_info.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/notification_inbox_action.dart';
import '../widgets/tournament_section_bar.dart';

enum _HomeTournamentFilter { recommended, thisWeek, all }

/// 지역 필터의 "전체" 항목. 지역 이름과 같은 자리에서 쓰이므로 상수로 둔다.
const String _allRegions = '전국';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedRegion = _allRegions;

  Future<void> _refresh() async {
    ref.invalidate(homeTournamentsProvider);
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(myClubsProvider);
    ref.invalidate(unreadNotificationCountProvider);
    await ref.read(homeTournamentsProvider.future);
  }

  List<Tournament> _visibleTournaments(
    List<Tournament> source,
    String selectedSport,
    String selectedRegion,
  ) {
    final sorted = [...source]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = sorted
        .where(
          (item) =>
              item.sport == selectedSport &&
              !item.startDate.isBefore(today) &&
              !item.isRegistrationClosed &&
              _matchesRegion(item, selectedRegion),
        )
        .toList(growable: false);
    return upcoming;
  }

  /// 지역을 골라도 전국대회(지역 값이 비어 있는 대회)는 함께 보여준다.
  /// 광주를 고른 사용자에게 광주에서 열리는 전국대회가 사라지면 안 된다.
  bool _matchesRegion(Tournament item, String selectedRegion) {
    if (selectedRegion == _allRegions) return true;
    final region = (item.region ?? '').trim();
    if (region.isEmpty) return true;
    return region.contains(selectedRegion);
  }

  /// 지역 선택지는 실제로 불러온 대회에서 뽑는다.
  /// 하드코딩하면 대회가 없는 지역이 남고(서울 0건) 대회가 가장 많은 지역이
  /// 빠지는(전남 15건) 어긋남이 반복된다.
  Map<String, int> _regionCounts(
    List<Tournament> source,
    String selectedSport,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = <String, int>{};
    for (final item in source) {
      if (item.sport != selectedSport) continue;
      if (item.startDate.isBefore(today)) continue;
      if (item.isRegistrationClosed) continue;
      // 전국대회는 모든 지역에 함께 나오므로 별도 항목으로 만들지 않는다.
      for (final part in (item.region ?? '').split('·')) {
        final name = part.trim();
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    final names = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return {for (final name in names) name: counts[name]!};
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
    final regionCounts = _regionCounts(source.value ?? const [], selectedSport);
    // 종목을 바꾸면 이전 종목에만 있던 지역이 남을 수 있어 전국으로 되돌린다.
    final selectedRegion =
        regionCounts.containsKey(_selectedRegion) ? _selectedRegion : _allRegions;

    return Scaffold(
      key: AllRoundE2EKeys.homeScreen,
      appBar: AppBar(
        // 종목을 타이틀로 올려 "지금 무엇을 보고 있는지"를 항상 보이게 하고,
        // 타이틀 자체가 종목 전환 버튼을 겸한다.
        title: _SportTitle(
          sport: selectedSport,
          onSelected: (value) =>
              ref.read(sportOverrideProvider.notifier).select(value),
        ),
        titleSpacing: AppSpacing.xl,
        bottom: const TournamentSectionBar(
          selected: TournamentSection.overview,
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
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _TournamentHomeControls(
                  selectedRegion: selectedRegion,
                  regionCounts: regionCounts,
                  onRegionSelected: (value) =>
                      setState(() => _selectedRegion = value),
                  onSearch: () => context.push('/tournaments?search=1'),
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
                final visible =
                    _visibleTournaments(items, selectedSport, selectedRegion);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
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
                      selectedRegion: selectedRegion,
                      onOpen: (item) => context.push('/tournaments/${item.id}'),
                      onFavorite: _toggleFavorite,
                      onBrowse: () => context.push('/tournaments'),
                      onFavorites: () => context.push('/favorites'),
                      onRules: () =>
                          context.push('/rules?sport=$selectedSport'),
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

class _TournamentHomeControls extends StatelessWidget {
  const _TournamentHomeControls({
    required this.selectedRegion,
    required this.regionCounts,
    required this.onRegionSelected,
    required this.onSearch,
  });

  final String selectedRegion;
  final Map<String, int> regionCounts;
  final ValueChanged<String> onRegionSelected;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 종목 버튼이 AppBar 타이틀로 올라가 이 줄에는 지역과 검색만 남는다.
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final region = _HomeMenuButton(
      icon: Icons.location_on_outlined,
      label: selectedRegion,
      values: {
        _allRegions: _allRegions,
        for (final entry in regionCounts.entries)
          entry.key: '${entry.key} ${entry.value}',
      },
      selectedValue: selectedRegion,
      onSelected: onRegionSelected,
    );
    // 홈 검색은 받아둔 목록만 훑어서 "있는 대회가 안 나오는" 결과를 만들었다.
    // 입력창이 아니라 서버가 전수 검색하는 전체 대회 화면의 입구로 쓴다.
    final search = TextField(
      readOnly: true,
      onTap: onSearch,
      decoration: InputDecoration(
        hintText: '대회명 또는 지역을 검색해보세요',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: cs.surfaceContainerLowest,
      ),
    );
    // 큰 글씨에서는 한 줄에 두 요소가 들어가지 않아 세로로 쌓는다.
    if (largeText) {
      return Column(
        children: [
          region,
          const SizedBox(height: AppSpacing.md),
          search,
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 132, child: region),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: search),
      ],
    );
  }
}

/// AppBar 타이틀 겸 종목 전환 버튼. 화살표가 있어야 눌리는 줄 안다.
class _SportTitle extends StatelessWidget {
  const _SportTitle({required this.sport, required this.onSelected});

  final String sport;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: sport,
      onSelected: onSelected,
      tooltip: '종목 바꾸기',
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'tennis',
          child: Text(sportLabel(Sport.tennis)),
        ),
        PopupMenuItem(
          value: 'futsal',
          child: Text(sportLabel(Sport.futsal)),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '올라운드 ${sportLabelFromString(sport)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
        ],
      ),
    );
  }
}

class _HomeMenuButton extends StatelessWidget {
  const _HomeMenuButton({
    required this.icon,
    required this.label,
    required this.values,
    required this.selectedValue,
    required this.onSelected,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final Map<String, String> values;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      initialValue: selectedValue,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final entry in values.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(
            color: emphasized ? cs.primary : cs.outlineVariant,
            width: emphasized ? 1.5 : 1,
          ),
          borderRadius: AppRadius.card,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: emphasized ? cs.primary : null),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          ],
        ),
      ),
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
    required this.selectedRegion,
    required this.onOpen,
    required this.onFavorite,
    required this.onBrowse,
    required this.onFavorites,
    required this.onRules,
  });

  final List<Tournament> tournaments;
  final List<Tournament> favorites;
  final Set<String> favoriteIds;
  final String selectedSport;
  final String selectedRegion;
  final ValueChanged<Tournament> onOpen;
  final Future<void> Function(Tournament, bool) onFavorite;
  final VoidCallback onBrowse;
  final VoidCallback onFavorites;
  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    final deadlineSoon = tournaments.where((item) {
      final deadline = item.applicationDeadline;
      if (deadline == null) return false;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = deadline.difference(today).inDays;
      return days >= 0 && days <= 7;
    }).toList();

    // 히어로는 "지금 신청해야 하는 것"을 맡는다. 마감 임박이 없을 때만
    // 다가오는 순서로 채운다.
    final heroItems =
        (deadlineSoon.isNotEmpty ? deadlineSoon : tournaments).take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heroItems.isNotEmpty) ...[
          if (deadlineSoon.isNotEmpty) ...[
            const _SectionTitle(title: '접수 마감 임박'),
            const SizedBox(height: AppSpacing.sm),
          ],
          _TournamentHero(tournaments: heroItems, onOpen: onOpen),
          const SizedBox(height: AppSpacing.xl),
        ],
        _InterestTournamentBand(
          tournaments: favorites,
          onOpen: onOpen,
          onBrowse: onBrowse,
          onFavorites: onFavorites,
        ),
        const SizedBox(height: AppSpacing.xxl),
        // 마감 임박 가로줄과 지역별 목록을 하나로 합쳤다. 예전에는 같은 대회가
        // 히어로·가로줄·목록에 최대 세 번 나왔다.
        _SectionTitle(
          title: '다가오는 대회',
          subtitle: selectedRegion,
          onAction: onBrowse,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (tournaments.isEmpty)
          AppEmptyState(
            key: AllRoundE2EKeys.homeEmptyState,
            icon: Icons.calendar_month_outlined,
            title: '예정된 대회가 없습니다',
            description: '지역을 전국으로 바꾸거나 전체 대회에서 찾아보세요.',
            actionLabel: '전체 대회 보기',
            onAction: onBrowse,
          )
        else
          for (final item in tournaments.take(5))
            _TournamentListCard(
              tournament: item,
              saved: favoriteIds.contains(item.id),
              onOpen: () => onOpen(item),
              onFavorite: () => onFavorite(item, favoriteIds.contains(item.id)),
            ),
        const SizedBox(height: AppSpacing.xxl),
        _RulebookBand(sport: selectedSport, onOpen: onRules),
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
    final hasPoster = widget.tournaments
        .any((item) => (item.posterUrl ?? '').trim().isNotEmpty);
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
    required this.onFavorites,
  });

  final List<Tournament> tournaments;
  final ValueChanged<Tournament> onOpen;
  final VoidCallback onBrowse;
  final VoidCallback onFavorites;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = tournaments.firstOrNull;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    final info = Row(
      children: [
        Icon(
          first == null
              ? Icons.favorite_border_rounded
              : Icons.favorite_rounded,
          color: cs.primary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                first?.title ?? '관심 대회가 없어요',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                first == null
                    ? '하트로 저장한 대회를 여기에 모아드려요'
                    : '관심 대회 ${tournaments.length}개',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
    final action = Semantics(
      button: true,
      child: InkWell(
        onTap: first == null ? onBrowse : onFavorites,
        borderRadius: AppRadius.pill,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: cs.primary),
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            first == null ? '대회 둘러보기' : '전체보기',
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: first == null ? onBrowse : () => onOpen(first),
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    info,
                    const SizedBox(height: AppSpacing.sm),
                    action,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: AppSpacing.sm),
                    action,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: 76,
                child: ClipRRect(
                  borderRadius: AppRadius.card,
                  child: _TournamentImage(tournament: tournament),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${DateFormat('M월 d일 (E)', 'ko').format(tournament.startDate)} · ${tournament.region ?? '지역 미정'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      tournament.applicationDeadline == null
                          ? '접수 중'
                          : '~${DateFormat('M/d').format(tournament.applicationDeadline!)} 접수',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    final url = tournament.posterUrl?.trim();
    final fallback = ColoredBox(
      color: const Color(0xFF102B62),
      child: Center(
        child: Icon(
          tournament.sport == 'tennis'
              ? Icons.sports_tennis_rounded
              : Icons.sports_soccer_rounded,
          size: 52,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.count,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        if (count != null) Text('$count개'),
        if (subtitle != null) Text(subtitle!),
        if (onAction != null)
          TextButton(onPressed: onAction, child: const Text('전체보기')),
      ],
    );
  }
}

class _RulebookBand extends StatelessWidget {
  const _RulebookBand({required this.sport, required this.onOpen});

  final String sport;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = sport == 'tennis' ? '테니스 룰북' : '풋살 룰북';
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.45),
      borderRadius: AppRadius.hero,
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppRadius.hero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              if (largeText)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const Text('경기 전에 꼭 알아둘 규칙'),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const Text('경기 전에 꼭 알아둘 규칙'),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              const Row(
                children: [
                  Expanded(child: _RuleItem(Icons.sports_rounded, '경기 진행')),
                  Expanded(child: _RuleItem(Icons.badge_outlined, '참가 자격')),
                  Expanded(
                      child: _RuleItem(Icons.scoreboard_outlined, '점수·승패')),
                  Expanded(
                      child: _RuleItem(Icons.warning_amber_rounded, '주의사항')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
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
  const _HomeSectionHeader(
      {required this.title, this.onAction, this.actionKey});

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
