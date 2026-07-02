import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
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
      if (AppConfig.userDesignPreview) {
        if (mounted) setState(() => _myClubs = _previewManagedClubs);
        return;
      }
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
      if (AppConfig.userDesignPreview) {
        if (mounted) setState(() => _clubs = _previewSearchClubs);
        return;
      }
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

  Future<void> _openCreate() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ClubCreateScreen()),
    );
    if (result == true) {
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
        title: '클럽 찾기 조건',
        icon: Icons.tune_rounded,
        accentColor: cs.primaryContainer,
        onAccentColor: cs.onPrimaryContainer,
      ),
    );
    if (result != null) {
      setState(() {
        _clubFilters = result.filters;
        _clubInterests = result.interests;
      });
      _load();
    }
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
    if (AppConfig.userDesignPreview) return;
    await ref.read(apiProvider).toggleClubFavorite(club.id, !isFavorite);
    ref.invalidate(clubFavoriteIdsProvider);
    ref.invalidate(myFavoriteClubsProvider);
  }

  Club? _clubForRecruitingPost(RecruitingPostPreview post) {
    final candidates = [
      ...?_clubs,
      ...?_myClubs,
      ..._previewSearchClubs,
      ..._previewManagedClubs,
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
    final cs = Theme.of(context).colorScheme;
    final favoriteClubIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    final effectiveClubs = _clubs ?? _previewSearchClubs;
    final visibleClubs = effectiveClubs
        .where((club) => _clubInterests.contains(club.sport))
        .where((club) => clubNameMatchesQuery(club.name, _clubNameQuery))
        .where((club) => _matchesClubFilters(club, _clubFilters))
        .toList();
    final hasClubNameQuery = _clubNameQuery.trim().isNotEmpty;
    final nearbyNewClubs = _nearbyRecentClubs(visibleClubs);
    final newClubs = nearbyNewClubs.take(4).toList();
    final recommendedClubs = _recommendedPreviewClubs(visibleClubs);
    final displayedRecommendationClubs =
        hasClubNameQuery ? recommendedClubs : recommendedClubs.take(3).toList();
    final joinedClubs = (_myClubs ?? _previewManagedClubs)
        .where((club) => club.isMember)
        .toList();
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
      body: CustomScrollView(
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
                _ClubSearchField(
                  value: _clubNameQuery,
                  onChanged: (value) => setState(() {
                    _clubNameQuery = value;
                  }),
                ),
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
                    style: TextStyle(color: cs.error),
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
                      ),
                    ),
                const SizedBox(height: AppSpacing.lg),
                // 내 주변 새 클럽(GPS 반경): 시현 이슈로 임시 숨김 (#97).
                if (_nearbyNewClubsEnabled) ...[
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
                SimpleActionCard(
                  icon: Icons.location_on_rounded,
                  title: '맞춤 조건 설정',
                  subtitle: [
                    _selectedSportLabel(_clubInterests),
                    ..._clubFilters.labels,
                  ].join(' · '),
                  action: '설정',
                  color: const Color(0xFFEAF7F1),
                  onTap: _openClubFilterSheet,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (managedClubs.isNotEmpty) ...[
                  SimpleActionCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: '팀원모집',
                    subtitle: '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                    color: const Color(0xFFEAF7F1),
                    onTap: () => _openTeamRecruitingSheet(managedClubs),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                TeamRecruitingBoard(
                  posts: _visibleRecruitingPosts(_clubInterests),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '가입한 클럽',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SimpleClubTile(
                  club: joinedClubs.isEmpty ? null : joinedClubs.first,
                  isFavorite: joinedClubs.isEmpty
                      ? false
                      : favoriteClubIds.contains(joinedClubs.first.id),
                  onFavoriteToggle: _toggleClubFavorite,
                ),
              ],
            ),
          ),
        ],
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

  List<Club> _recommendedPreviewClubs(List<Club> source) {
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

  List<RecruitingPostPreview> _visibleRecruitingPosts(Set<String> interests) {
    final now = DateTime.now();
    final posts = [
      for (final post in _previewRecruitingPosts)
        if (_closedRecruitingPostIds.contains(post.id) && !post.isClosed)
          post.copyWith(isClosed: true, closedAt: now)
        else
          post,
    ].where((post) {
      if (!interests.contains(post.sport)) return false;
      if (post.isClosed && post.closedAt != null) {
        // Keep just-closed recruiting posts visible briefly so managers can
        // confirm the state change, then remove them from the public list.
        return now.difference(post.closedAt!).inHours < 24;
      }
      return true;
    }).toList();

    if (_showOpenRecruitingOnly) {
      return posts.where((post) => !post.isClosed).toList();
    }
    return posts;
  }
}

class _ClubSearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ClubSearchField({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ClubSearchField> createState() => _ClubSearchFieldState();
}

class _ClubSearchFieldState extends State<_ClubSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ClubSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '클럽 이름으로 검색',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: widget.value.isEmpty
            ? null
            : IconButton(
                tooltip: '검색어 지우기',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

final _previewManagedClubs = [
  Club(
    id: 'preview-managed-futsal',
    sport: 'futsal',
    name: '광주 위너스 풋살클럽',
    region: '광주',
    address: '광주 북구 풋살파크',
    description: '주말 저녁 풋살 멤버를 모집하는 클럽',
    memberCount: 18,
    myRole: 'owner',
  ),
  Club(
    id: 'preview-managed-tennis',
    sport: 'tennis',
    name: '올라운드 테니스 크루',
    region: '광주',
    address: '염주실내테니스장',
    description: '초보부터 함께 치는 테니스 모임',
    memberCount: 24,
    myRole: 'manager',
  ),
];

final _previewRecruitingPosts = [
  RecruitingPostPreview(
    id: 'preview-recruiting-futsal-open-1',
    sport: 'futsal',
    clubName: '광주 위너스 풋살클럽',
    title: '주말 저녁 정기전 팀원 모집',
    region: '광주',
    place: '광주 북구 풋살파크 A구장',
    schedule: '6/22 (토) 19:00',
    grade: '초급 · 중급',
    gender: '혼성',
    age: '20대 · 30대',
    fieldCount: 4,
    keeperCount: 1,
    totalCount: 5,
    cost: '10,000원',
    intro: '정기적으로 주말 저녁에 뛰는 팀입니다. 초급자도 부담 없이 참여할 수 있어요.',
  ),
  RecruitingPostPreview(
    id: 'preview-recruiting-tennis-open-1',
    sport: 'tennis',
    clubName: '올라운드 테니스 크루',
    title: '토요일 복식 랠리 멤버 모집',
    region: '광주',
    place: '염주실내테니스장',
    schedule: '6/29 (토) 10:00',
    grade: '신입 · 5부',
    gender: '무관',
    age: '무관',
    fieldCount: 0,
    keeperCount: 0,
    totalCount: 2,
    cost: '코트비 N분의 1',
    intro: '복식 랠리를 함께할 멤버를 찾고 있습니다. 랠리가 가능한 초보도 환영합니다.',
  ),
  RecruitingPostPreview(
    id: 'preview-recruiting-futsal-closed-1',
    sport: 'futsal',
    clubName: '리얼 FS 신규회원 모집중',
    title: '평일 야간 풋살 게스트 모집',
    region: '광주',
    place: '첨단 풋살파크',
    schedule: '6/19 (수) 21:00',
    grade: '입문 · 초급',
    gender: '남성',
    age: '30대',
    fieldCount: 0,
    keeperCount: 0,
    totalCount: 0,
    cost: '마감',
    intro: '평일 야간에 가볍게 합류할 게스트를 모집했던 글입니다.',
    isClosed: true,
    closedAt: DateTime(2026, 6, 17, 18),
  ),
];

final _previewSearchClubs = [
  Club(
    id: 'preview-new-futsal-1',
    sport: 'futsal',
    name: '리얼 FS 신규회원 모집중',
    region: '광주',
    address: '광주 북구 풋살파크',
    description: '평일 저녁과 주말에 함께 뛰는 풋살 클럽',
    memberCount: 78,
    meetingDays: const ['화', '목', '토'],
    monthlyFee: 30000,
    genderPreference: 'mixed',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  Club(
    id: 'preview-new-tennis-1',
    sport: 'tennis',
    name: '올라운드 테니스 크루',
    region: '광주',
    address: '염주실내테니스장',
    description: '초보부터 랠리까지 함께 치는 테니스 모임',
    memberCount: 24,
    meetingDays: const ['수', '토'],
    monthlyFee: 20000,
    genderPreference: 'mixed',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  Club(
    id: 'preview-new-futsal-2',
    sport: 'futsal',
    name: '광주 위너스 풋살클럽',
    region: '광주',
    address: '수완 풋살파크',
    description: '초급자도 참여 가능한 주말 풋살 클럽',
    memberCount: 32,
    meetingDays: const ['일'],
    monthlyFee: 10000,
    genderPreference: 'male',
    createdAt: DateTime.now().subtract(const Duration(days: 5)),
  ),
  Club(
    id: 'preview-new-tennis-2',
    sport: 'tennis',
    name: '광주 랠리메이트',
    region: '광주',
    address: '상무 테니스코트',
    description: '퇴근 후 가볍게 치는 직장인 테니스 클럽',
    memberCount: 41,
    meetingDays: const ['월', '목'],
    monthlyFee: 40000,
    genderPreference: 'mixed',
    createdAt: DateTime.now().subtract(const Duration(days: 6)),
  ),
  Club(
    id: 'preview-rec-futsal-1',
    sport: 'futsal',
    name: '첨단 풋살 러닝메이트',
    region: '광주',
    address: '첨단 풋살센터',
    description: '입문자와 초급자가 편하게 참여하는 모임',
    memberCount: 18,
    meetingDays: const ['금'],
    monthlyFee: 0,
    genderPreference: 'mixed',
    createdAt: DateTime.now().subtract(const Duration(days: 14)),
  ),
  Club(
    id: 'preview-rec-tennis-1',
    sport: 'tennis',
    name: '주말 테니스 친구들',
    region: '광주',
    address: '광주 월드컵 테니스장',
    description: '주말 오전 중심의 테니스 동호회',
    memberCount: 56,
    meetingDays: const ['토', '일'],
    monthlyFee: 50000,
    genderPreference: 'mixed',
    createdAt: DateTime.now().subtract(const Duration(days: 21)),
  ),
];
