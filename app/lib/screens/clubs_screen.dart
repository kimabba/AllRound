import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/club_recruiting.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/club_labels.dart';
import '../utils/club_sort.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/clubs/club_filter_widgets.dart';
import '../widgets/clubs/club_section_widgets.dart';
import '../widgets/clubs/club_tiles.dart';
import '../widgets/clubs/team_recruiting_widgets.dart';
import '../widgets/notification_inbox_action.dart';
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
  List<Club> _pendingClubs = const <Club>[];
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
  ClubSortOrder _clubSortOrder = ClubSortOrder.recommended;
  List<RecruitingPostPreview> _recruitingPosts = const [];
  bool _loadingRecruiting = false;

  @override
  void initState() {
    super.initState();
    _clubInterests = {ref.read(activeSportProvider) ?? 'futsal'};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
      _loadRecruitingPosts();
      _restoreClubSortOrder();
    });
  }

  Future<void> _restoreClubSortOrder() async {
    final order = await loadClubSortOrder();
    if (mounted) setState(() => _clubSortOrder = order);
  }

  Future<void> _selectClubSortOrder(ClubSortOrder? order) async {
    if (order == null || order == _clubSortOrder) return;
    setState(() => _clubSortOrder = order);
    await saveClubSortOrder(order);
  }

  Future<void> _loadMyClubs() async {
    setState(() => _loadingMy = true);
    if (AppConfig.userDesignPreview) {
      setState(() {
        _myClubs = _previewMyClubs;
        _loadingMy = false;
      });
      return;
    }
    try {
      final list = await ref.read(apiProvider).myClubs();
      if (mounted) setState(() => _myClubs = list);
    } catch (e) {
      debugPrint('myClubs error: $e');
      if (mounted) setState(() => _myClubs = []);
    } finally {
      if (mounted) setState(() => _loadingMy = false);
    }
    // pending 조회 실패가 이미 로드된 가입 클럽 목록을 지우지 않도록 별도 처리.
    try {
      final pending = await ref.read(apiProvider).myPendingJoinRequests();
      if (mounted) setState(() => _pendingClubs = pending);
    } catch (e) {
      debugPrint('myPendingJoinRequests error: $e');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _searchError = null;
    });
    if (AppConfig.userDesignPreview) {
      setState(() {
        _clubs = _previewClubs;
        _loading = false;
      });
      return;
    }
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

  Future<void> _loadRecruitingPosts() async {
    setState(() => _loadingRecruiting = true);
    if (AppConfig.userDesignPreview) {
      setState(() {
        _recruitingPosts = _previewRecruitingPosts;
        _loadingRecruiting = false;
      });
      return;
    }
    try {
      final posts = await ref.read(apiProvider).teamRecruitingPosts();
      if (mounted) setState(() => _recruitingPosts = posts);
    } catch (error) {
      debugPrint('teamRecruitingPosts error: $error');
      if (mounted) setState(() => _recruitingPosts = const []);
    } finally {
      if (mounted) setState(() => _loadingRecruiting = false);
    }
  }

  Future<void> _refreshClubLists() async {
    ref.invalidate(myClubsProvider);
    ref.invalidate(myFavoriteClubsProvider);
    await Future.wait([
      _loadMyClubs(),
      _load(),
      _loadRecruitingPosts(),
    ]);
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
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
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
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TeamRecruitingDraftSheet(managedClubs: managedClubs),
    );
    if (created == true) {
      await _loadRecruitingPosts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀원 모집글을 올렸습니다.')),
      );
    }
  }

  Future<void> _openNearbyNewClubsSheet(List<Club> clubs) async {
    final favoriteIds =
        ref.read(clubFavoriteIdsProvider).value ?? const <String>{};
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
    if (AppConfig.userDesignPreview) return;
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
      if (club.id == post.clubId) {
        return club;
      }
    }
    return null;
  }

  Future<void> _openRecruitingDetail(RecruitingPostPreview post) async {
    Club? club = _clubForRecruitingPost(post);
    if (club == null) {
      try {
        club = await ref.read(apiProvider).getClub(post.clubId);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('클럽 정보를 불러오지 못했습니다.')),
        );
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamRecruitingDetailScreen(
          post: post,
          club: club,
        ),
      ),
    );
  }

  Future<void> _closeRecruitingPost(RecruitingPostPreview post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모집을 마감할까요?'),
        content: Text('“${post.title}” 글은 마감 후 다시 열 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('마감하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(apiProvider).closeTeamRecruitingPost(post.id);
      await _loadRecruitingPosts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀원 모집을 마감했습니다.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집을 마감하지 못했습니다.')),
      );
    }
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
        ref.watch(clubFavoriteIdsProvider).value ?? const <String>{};
    final effectiveClubs = _clubs ?? const <Club>[];
    final visibleClubs = effectiveClubs
        .where((club) => _clubInterests.contains(club.sport))
        .where((club) => clubNameMatchesQuery(club.name, _clubNameQuery))
        .where((club) => _matchesClubFilters(club, _clubFilters))
        .toList();
    final hasClubNameQuery = _clubNameQuery.trim().isNotEmpty;
    final nearbyNewClubs = _nearbyRecentClubs(visibleClubs);
    final newClubs = nearbyNewClubs.take(4).toList();
    final recommendedClubs = _clubSortOrder == ClubSortOrder.recommended
        ? _recommendedClubs(visibleClubs)
        : sortClubs(visibleClubs, _clubSortOrder);
    final displayedRecommendationClubs = hasClubNameQuery || _showAllClubs
        ? recommendedClubs
        : recommendedClubs.take(3).toList();
    final myMembershipClubs =
        (_myClubs ?? const <Club>[]).where((club) => club.isMember).toList();
    final joinedClubs =
        myMembershipClubs.where((club) => club.isApproved).toList();
    // 승인 대기중 가입신청 — 이미 멤버인 클럽은 제외.
    final pendingClubs = _pendingClubs
        .where((p) => !joinedClubs.any((j) => j.id == p.id))
        .toList();
    final managedClubs = joinedClubs.where((club) => club.isManager).toList();

    return Scaffold(
      key: AllRoundE2EKeys.clubsScreen,
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('클럽'),
        actions: [
          const NotificationInboxAction(),
          TextButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('만들기'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshClubLists,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                96,
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
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<ClubSortOrder>(
                        value: _clubSortOrder,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        icon: const Icon(Icons.sort_rounded),
                        onChanged: _selectClubSortOrder,
                        items: [
                          for (final order in ClubSortOrder.values)
                            DropdownMenuItem(
                              value: order,
                              child: Text(order.label),
                            ),
                        ],
                      ),
                    ),
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
                    isLoading: _loadingRecruiting,
                    managedClubIds: managedClubs.map((club) => club.id).toSet(),
                    onShowOpenOnlyChanged: (value) {
                      setState(() => _showOpenRecruitingOnly = value);
                    },
                    onClosePost: _closeRecruitingPost,
                    onOpenPost: _openRecruitingDetail,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SimpleSectionHeader(title: '가입한 클럽'),
                  const SizedBox(height: AppSpacing.sm),
                  if (joinedClubs.isEmpty && pendingClubs.isEmpty)
                    SimpleClubTile(
                      club: null,
                      onFavoriteToggle: _toggleClubFavorite,
                    )
                  else ...[
                    for (final club in pendingClubs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: SimpleClubTile(
                          club: club,
                          pending: true,
                          isFavorite: favoriteClubIds.contains(club.id),
                          onFavoriteToggle: _toggleClubFavorite,
                          onOpen: () => _openClub(club),
                        ),
                      ),
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
    return _recruitingPosts
        .where((post) => _clubInterests.contains(post.sport))
        .where((post) => !_showOpenRecruitingOnly || !post.isClosed)
        .toList(growable: false);
  }
}

final _previewClubs = [
  Club(
    id: 'preview-club-futsal',
    sport: 'futsal',
    name: '서울 풋살 러너스',
    region: '서울',
    address: '서울 송파구 잠실동',
    description: '주말 저녁, 꾸준히 함께 뛰는 생활체육 풋살 클럽입니다.',
    memberCount: 24,
    meetingDays: const ['토', '일'],
    monthlyFee: 30000,
    genderPreference: 'mixed',
    contact: '오픈채팅 문의',
    createdAt: DateTime(2026, 7, 10),
  ),
  Club(
    id: 'preview-club-futsal-2',
    sport: 'futsal',
    name: '한강 풋살 유나이티드',
    region: '서울',
    address: '서울 마포구 망원동',
    description: '초중급 중심으로 매주 수요일 저녁에 운동합니다.',
    memberCount: 18,
    meetingDays: const ['수'],
    monthlyFee: 25000,
    genderPreference: 'mixed',
    createdAt: DateTime(2026, 6, 22),
  ),
  Club(
    id: 'preview-club-tennis',
    sport: 'tennis',
    name: '광주 테니스 크루',
    region: '광주',
    address: '광주 서구 풍암동',
    description: '초중급 복식 위주로 함께 치는 테니스 클럽입니다.',
    memberCount: 38,
    meetingDays: const ['화', '목'],
    monthlyFee: 20000,
    genderPreference: 'mixed',
    createdAt: DateTime(2026, 5, 8),
  ),
];

final _previewMyClubs = [
  Club(
    id: 'preview-club-my',
    sport: 'futsal',
    name: '성수 풋살 메이트',
    region: '서울',
    address: '서울 성동구 성수동',
    description: '평일 퇴근 후 가볍게 뛰는 직장인 풋살 모임입니다.',
    memberCount: 16,
    meetingDays: const ['목'],
    monthlyFee: 20000,
    myRole: 'member',
  ),
];

final _previewRecruitingPosts = [
  RecruitingPostPreview(
    id: 'preview-recruiting-1',
    clubId: 'preview-club-futsal',
    sport: 'futsal',
    clubName: '서울 풋살 러너스',
    title: '토요일 저녁 필드 플레이어 모집',
    region: '서울',
    place: '잠실 풋살장',
    schedule: '매주 토요일 19:00',
    grade: '초중급',
    gender: '무관',
    age: '20–40대',
    position: '필드',
    fieldCount: 3,
    keeperCount: 1,
    totalCount: 4,
    cost: '회당 1만원',
    intro: '기본 매너를 지키며 꾸준히 함께할 멤버를 찾습니다.',
    createdAt: DateTime(2026, 7, 17),
  ),
];
