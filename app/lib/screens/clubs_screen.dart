import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/club_labels.dart';
import '../utils/grade_labels.dart';
import '../widgets/allround_logo.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/clubs/club_filter_widgets.dart';
import '../widgets/clubs/club_section_widgets.dart';
import '../widgets/clubs/club_tiles.dart';
import '../widgets/clubs/team_recruiting_widgets.dart';
import 'clubs/club_create_screen.dart';
import 'clubs/club_detail_screen.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  // 내 주변 새 클럽(GPS 반경): 시현 이슈로 임시 숨김. GPS 기반 재구현 예정 (#97).
  // false → 섹션 미노출. 코드·헬퍼는 보존하므로 true 로 되돌리면 복구됨.
  final bool _nearbyNewClubsEnabled = false;

  // 내 클럽 탭
  List<Club>? _myClubs;
  bool _loadingMy = false;

  // 클럽 찾기 탭
  List<Club>? _clubs;
  bool _loading = false;
  String? _searchError;
  String _clubNameQuery = '';
  ClubSearchFilters _clubFilters = const ClubSearchFilters();
  late Set<String> _clubInterests;
  bool _showOpenRecruitingOnly = false;
  bool _showAllClubs = false;
  final Set<String> _closedRecruitingPostIds = {};

  @override
  void initState() {
    super.initState();
    _clubInterests = {ref.read(activeSportProvider) ?? 'futsal'};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
    });
  }

  Future<void> _loadMyClubs() async {
    setState(() => _loadingMy = true);
    try {
      final list = await ref.read(apiProvider).myClubs();
      if (mounted) setState(() => _myClubs = list);
    } catch (e) {
      debugPrint('myClubs error: $e');
      if (mounted) setState(() => _myClubs = []);
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _searchError = null;
    });
    try {
      final api = ref.read(apiProvider);
      final sports = _clubInterests.isEmpty
          ? const <String>['tennis', 'futsal']
          : _clubInterests.toList();
      final results = await Future.wait(
        sports.map(
          (sport) => api.searchClubs(
            sport: sport,
            region: _clubFilters.region,
          ),
        ),
      );
      final seen = <String>{};
      final list = [
        for (final clubs in results)
          for (final club in clubs)
            if (seen.add(club.id)) club,
      ];
      if (mounted) setState(() => _clubs = list);
    } catch (_) {
      if (mounted) setState(() => _searchError = '클럽 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshClubLists() async {
    ref.invalidate(myClubsProvider);
    ref.invalidate(myFavoriteClubsProvider);
    await Future.wait([_loadMyClubs(), _load()]);
  }

  Future<void> _openCreate() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClubCreateScreen()),
    );
    if (result == true) {
      ref.invalidate(myClubsProvider);
      _loadMyClubs();
      _load();
    }
  }

  Future<void> _openClubFilterSheet() async {
    final cs = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<ClubFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ClubFilterSheet(
        initialFilters: _clubFilters,
        initialInterests: _clubInterests,
        initialNameQuery: _clubNameQuery,
        title: '상세검색',
        icon: Icons.tune_rounded,
        accentColor: cs.primaryContainer,
        onAccentColor: cs.onPrimaryContainer,
      ),
    );
    if (result != null) {
      setState(() {
        _clubFilters = result.filters;
        _clubInterests = result.interests;
        _clubNameQuery = result.nameQuery;
      });
      _load();
    }
  }

  /// 대회 탭과 동일한 패턴: 상단엔 '기준 · 상세검색' 바 하나만 두고,
  /// 검색창은 상세검색 bottom sheet 안에서 노출한다.
  Widget _buildClubFilterControls(ColorScheme cs, bool hasClubNameQuery) {
    final tt = Theme.of(context).textTheme;
    final active = hasClubNameQuery || _clubFilters.hasActive;
    final parts = <String>[
      _selectedSportLabel(_clubInterests),
      if (hasClubNameQuery) '검색어',
      ..._clubFilters.labels,
    ];
    final filterLabel =
        active ? '${parts.join(' · ')} 적용됨' : '${parts.join(' · ')} 전체 클럽 기준';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune_rounded,
            size: 19,
            color: active ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              filterLabel,
              style: tt.labelLarge?.copyWith(
                color: active ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _openClubFilterSheet,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('상세검색'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTeamRecruitingSheet(List<Club> managedClubs) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TeamRecruitingDraftSheet(managedClubs: managedClubs),
    );
  }

  Future<void> _openNearbyNewClubsSheet(List<Club> clubs) async {
    final favoriteIds =
        ref.read(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NearbyNewClubsSheet(
        clubs: clubs,
        favoriteIds: favoriteIds,
        onFavoriteToggle: _toggleClubFavorite,
      ),
    );
  }

  Future<void> _toggleClubFavorite(Club club, bool isFavorite) async {
    await ref.read(apiProvider).toggleClubFavorite(club.id, !isFavorite);
    ref.invalidate(clubFavoriteIdsProvider);
    ref.invalidate(myFavoriteClubsProvider);
  }

  Club? _clubForRecruitingPost(RecruitingPostPreview post) {
    final candidates = [
      ...?_clubs,
      ...?_myClubs,
    ];
    for (final club in candidates) {
      if (club.name == post.clubName && club.sport == post.sport) {
        return club;
      }
    }
    return null;
  }

  Future<void> _openRecruitingDetail(RecruitingPostPreview post) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamRecruitingDetailScreen(
          post: post,
          club: _clubForRecruitingPost(post),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeSportProvider, (previous, next) {
      if (next == null || next == previous) return;
      setState(() {
        _clubInterests = {next};
        _showAllClubs = false;
      });
      _load();
    });
    final cs = Theme.of(context).colorScheme;
    final favoriteClubIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    final effectiveClubs = _clubs ?? const <Club>[];
    final visibleClubs = effectiveClubs
        .where((club) => _clubInterests.contains(club.sport))
        .where((club) => clubNameMatchesQuery(club.name, _clubNameQuery))
        .where((club) => _matchesClubFilters(club, _clubFilters))
        .toList();
    final hasClubNameQuery = _clubNameQuery.trim().isNotEmpty;
    final nearbyNewClubs = _nearbyRecentClubs(visibleClubs);
    final newClubs = nearbyNewClubs.take(4).toList();
    final recommendedClubs = _recommendedClubs(visibleClubs);
    final displayedRecommendationClubs = hasClubNameQuery || _showAllClubs
        ? recommendedClubs
        : recommendedClubs.take(3).toList();
    final myMembershipClubs =
        (_myClubs ?? const <Club>[]).where((club) => club.isMember).toList();
    final joinedClubs =
        myMembershipClubs.where((club) => club.isApproved).toList();
    final managedClubs = joinedClubs.where((club) => club.isManager).toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const BrandedAppBarTitle(title: '클럽'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('클럽 만들기'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshClubLists,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                112,
              ),
              sliver: SliverList.list(
                children: [
                  _buildClubFilterControls(cs, hasClubNameQuery),
                  const SizedBox(height: AppSpacing.lg),
                  SimpleSectionHeader(
                    title: hasClubNameQuery ? '검색결과' : '맞춤추천',
                    subtitle: hasClubNameQuery
                        ? '"${_clubNameQuery.trim()}"'
                        : (_clubFilters.hasActive
                            ? [
                                _selectedSportLabel(_clubInterests),
                                ..._clubFilters.labels,
                              ].join(' · ')
                            : '${_selectedSportLabel(_clubInterests)} 기준'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_loading || _loadingMy) const LinearProgressIndicator(),
                  if (_searchError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _searchError!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.error),
                    ),
                  ],
                  if (displayedRecommendationClubs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: AppEmptyState(
                        icon: Icons.search_off_rounded,
                        title: '조건에 맞는 클럽이 없습니다',
                        description: '검색어를 줄이거나 맞춤 조건을 바꿔보세요.',
                      ),
                    )
                  else
                    for (final club in displayedRecommendationClubs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: SimpleClubTile(
                          club: club,
                          isFavorite: favoriteClubIds.contains(club.id),
                          onFavoriteToggle: _toggleClubFavorite,
                          onOpen: () => _openClub(club),
                        ),
                      ),
                  if (!hasClubNameQuery) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showAllClubs = !_showAllClubs;
                            if (_showAllClubs) {
                              _clubInterests = {'tennis', 'futsal'};
                            }
                          });
                          if (_showAllClubs) _load();
                        },
                        icon: Icon(
                          _showAllClubs
                              ? Icons.expand_less_rounded
                              : Icons.groups_2_outlined,
                        ),
                        label: Text(_showAllClubs ? '접기' : '전체 클럽 더보기'),
                      ),
                    ),
                  ],
                  // 내 주변 새 클럽(GPS 반경): 시현 이슈로 임시 숨김 (#97).
                  if (_nearbyNewClubsEnabled) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SimplePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SimpleSectionHeader(
                            title: '내 주변에 새로 생겼어요',
                            subtitle: '반경 5km · 최근 7일',
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (_loading || _loadingMy)
                            const LinearProgressIndicator(),
                          if (_searchError != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _searchError!,
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          SimpleClubGrid(
                            clubs: newClubs,
                            favoriteIds: favoriteClubIds,
                            onFavoriteToggle: _toggleClubFavorite,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openNearbyNewClubsSheet(nearbyNewClubs),
                              icon: const Icon(Icons.near_me_rounded),
                              label: const Text('내 주변 새 클럽 더보기'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (managedClubs.isNotEmpty) ...[
                    SimpleActionCard(
                      icon: Icons.person_add_alt_1_rounded,
                      title: '팀원모집',
                      subtitle:
                          '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                      color: cs.secondaryContainer,
                      onTap: () => _openTeamRecruitingSheet(managedClubs),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  TeamRecruitingBoard(
                    posts: _visibleRecruitingPosts(),
                    showOpenOnly: _showOpenRecruitingOnly,
                    canManage: managedClubs.isNotEmpty,
                    onShowOpenOnlyChanged: (value) {
                      setState(() => _showOpenRecruitingOnly = value);
                    },
                    onClosePost: (post) {
                      setState(() => _closedRecruitingPostIds.add(post.id));
                    },
                    onOpenPost: _openRecruitingDetail,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SimpleSectionHeader(title: '가입한 클럽'),
                  const SizedBox(height: AppSpacing.sm),
                  if (joinedClubs.isEmpty)
                    SimpleClubTile(
                      club: null,
                      onFavoriteToggle: _toggleClubFavorite,
                    )
                  else
                    for (final club in joinedClubs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: SimpleClubTile(
                          club: club,
                          isFavorite: favoriteClubIds.contains(club.id),
                          onFavoriteToggle: _toggleClubFavorite,
                          onOpen: () => _openClub(club),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesClubFilters(Club club, ClubSearchFilters filters) {
    if (filters.region != null &&
        !clubRegionMatches(club.region, filters.region!)) {
      return false;
    }
    if (filters.gender != null &&
        !clubGenderMatches(club.genderPreference, filters.gender!)) {
      return false;
    }
    if (!clubDaysMatch(club.meetingDays, filters.days)) {
      return false;
    }
    if (club.monthlyFee != null &&
        (club.monthlyFee! < filters.feeRange.start ||
            club.monthlyFee! > filters.feeRange.end)) {
      return false;
    }
    return true;
  }

  Future<void> _openClub(Club club) async {
    final result = await context.push<ClubDetailResult>(
      '/clubs/${club.id}',
      extra: club,
    );
    if (!mounted) return;

    if (result == ClubDetailResult.deleted) {
      setState(() {
        _clubs?.removeWhere((item) => item.id == club.id);
        _myClubs?.removeWhere((item) => item.id == club.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클럽이 삭제되었습니다.')),
      );
    } else if (result == ClubDetailResult.membershipChanged) {
      setState(() {
        _myClubs?.removeWhere((item) => item.id == club.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클럽에서 탈퇴했습니다.')),
      );
    }

    await _refreshClubLists();
  }

  String _selectedSportLabel(Set<String> interests) {
    if (interests.length == 1 && interests.isNotEmpty) {
      return sportLabelFromString(interests.first);
    }
    return '테니스 · 풋살';
  }

  List<Club> _nearbyRecentClubs(List<Club> source) {
    final now = DateTime.now();
    return source.where((club) {
      final createdAt = club.createdAt;
      if (createdAt == null) return false;
      return now.difference(createdAt).inDays <= 7;
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  List<Club> _recommendedClubs(List<Club> source) {
    final scored = [
      for (final club in source)
        (
          club: club,
          score: (_clubFilters.region != null &&
                      clubRegionMatches(club.region, _clubFilters.region!)
                  ? 4
                  : 0) +
              (_clubFilters.days.isNotEmpty &&
                      clubDaysMatch(club.meetingDays, _clubFilters.days)
                  ? 2
                  : 0) +
              club.memberCount,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((item) => item.club).toList();
  }

  List<RecruitingPostPreview> _visibleRecruitingPosts() {
    return const <RecruitingPostPreview>[];
  }
}
