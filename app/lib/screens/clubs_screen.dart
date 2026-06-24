import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/matchup_logo.dart';
import 'clubs/club_create_screen.dart';

typedef _ClubFavoriteToggle = Future<void> Function(
  Club club,
  bool isFavorite,
);

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
  _ClubSearchFilters _clubFilters = const _ClubSearchFilters();
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
    } catch (_) {
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
    final result = await showModalBottomSheet<_ClubFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClubFilterSheet(
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
      builder: (_) => _TeamRecruitingDraftSheet(managedClubs: managedClubs),
    );
  }

  Future<void> _openNearbyNewClubsSheet(List<Club> clubs) async {
    final favoriteIds =
        ref.read(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NearbyNewClubsSheet(
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favoriteClubIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};
    final effectiveClubs = _clubs ?? _previewSearchClubs;
    final visibleClubs = effectiveClubs
        .where((club) => _clubInterests.contains(club.sport))
        .where((club) => _matchesClubFilters(club, _clubFilters))
        .toList();
    final nearbyNewClubs = _nearbyRecentClubs(visibleClubs);
    final newClubs = nearbyNewClubs.take(4).toList();
    final recommendedClubs = _recommendedPreviewClubs(visibleClubs);
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
                // 내 주변 새 클럽(GPS 반경): 시현 이슈로 임시 숨김 (#97).
                if (_nearbyNewClubsEnabled) ...[
                  _SimplePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SimpleSectionHeader(
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
                        _SimpleClubGrid(
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
                _SimpleActionCard(
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
                  _SimpleActionCard(
                    icon: Icons.person_add_alt_1_rounded,
                    title: '팀원모집',
                    subtitle: '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                    color: const Color(0xFFEAF7F1),
                    onTap: () => _openTeamRecruitingSheet(managedClubs),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
                _TeamRecruitingBoard(
                  posts: _visibleRecruitingPosts(_clubInterests),
                  showOpenOnly: _showOpenRecruitingOnly,
                  canManage: managedClubs.isNotEmpty,
                  onShowOpenOnlyChanged: (value) {
                    setState(() => _showOpenRecruitingOnly = value);
                  },
                  onClosePost: (post) {
                    setState(() => _closedRecruitingPostIds.add(post.id));
                  },
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
                _SimpleClubTile(
                  club: joinedClubs.isEmpty ? null : joinedClubs.first,
                  isFavorite: joinedClubs.isEmpty
                      ? false
                      : favoriteClubIds.contains(joinedClubs.first.id),
                  onFavoriteToggle: _toggleClubFavorite,
                ),
                const SizedBox(height: AppSpacing.xl),
                _SimpleSectionHeader(
                  title: '맞춤추천',
                  subtitle: _clubFilters.hasActive
                      ? [
                          _selectedSportLabel(_clubInterests),
                          ..._clubFilters.labels,
                        ].join(' · ')
                      : '${_selectedSportLabel(_clubInterests)} 기준',
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final club in recommendedClubs.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _SimpleClubTile(
                      club: club,
                      isFavorite: favoriteClubIds.contains(club.id),
                      onFavoriteToggle: _toggleClubFavorite,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesClubFilters(Club club, _ClubSearchFilters filters) {
    if (filters.region != null && club.region != filters.region) return false;
    if (filters.gender != null &&
        club.genderPreference != null &&
        club.genderPreference != filters.gender) {
      return false;
    }
    if (filters.days.isNotEmpty &&
        club.meetingDays.isNotEmpty &&
        club.meetingDays.every((day) => !filters.days.contains(day))) {
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
    if (interests.length == 1) {
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
                      club.region == _clubFilters.region
                  ? 4
                  : 0) +
              (_clubFilters.days.isNotEmpty &&
                      club.meetingDays.any(_clubFilters.days.contains)
                  ? 2
                  : 0) +
              club.memberCount,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((item) => item.club).toList();
  }

  List<_RecruitingPostPreview> _visibleRecruitingPosts(Set<String> interests) {
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

class _RecruitingPostPreview {
  final String id;
  final String sport;
  final String clubName;
  final String title;
  final String region;
  final String place;
  final String schedule;
  final String grade;
  final String gender;
  final String age;
  final int fieldCount;
  final int keeperCount;
  final int totalCount;
  final String cost;
  final bool isClosed;
  final DateTime? closedAt;

  const _RecruitingPostPreview({
    required this.id,
    required this.sport,
    required this.clubName,
    required this.title,
    required this.region,
    required this.place,
    required this.schedule,
    required this.grade,
    required this.gender,
    required this.age,
    required this.fieldCount,
    required this.keeperCount,
    required this.totalCount,
    required this.cost,
    this.isClosed = false,
    this.closedAt,
  });

  _RecruitingPostPreview copyWith({
    bool? isClosed,
    DateTime? closedAt,
  }) {
    return _RecruitingPostPreview(
      id: id,
      sport: sport,
      clubName: clubName,
      title: title,
      region: region,
      place: place,
      schedule: schedule,
      grade: grade,
      gender: gender,
      age: age,
      fieldCount: fieldCount,
      keeperCount: keeperCount,
      totalCount: totalCount,
      cost: cost,
      isClosed: isClosed ?? this.isClosed,
      closedAt: closedAt ?? this.closedAt,
    );
  }

  String get countLabel {
    if (sport == 'futsal') {
      return '필드 $fieldCount명 · 키퍼 $keeperCount명';
    }
    return '$totalCount명';
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
  _RecruitingPostPreview(
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
  ),
  _RecruitingPostPreview(
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
  ),
  _RecruitingPostPreview(
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
    genderPreference: '혼성',
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
    genderPreference: '혼성',
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
    genderPreference: '남성',
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
    genderPreference: '혼성',
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
    genderPreference: '혼성',
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
    genderPreference: '혼성',
    createdAt: DateTime.now().subtract(const Duration(days: 21)),
  ),
];

class _SimpleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SimpleSectionHeader({
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimplePanel extends StatelessWidget {
  final Widget child;

  const _SimplePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SimpleClubGrid extends StatelessWidget {
  final List<Club> clubs;
  final Set<String> favoriteIds;
  final _ClubFavoriteToggle? onFavoriteToggle;

  const _SimpleClubGrid({
    required this.clubs,
    required this.favoriteIds,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final club in clubs.take(4))
          SizedBox(
            width: 180,
            child: _SimpleClubMiniTile(
              club: club,
              isFavorite: favoriteIds.contains(club.id),
              onFavoriteToggle: onFavoriteToggle,
            ),
          ),
      ],
    );
  }
}

class _NearbyNewClubsSheet extends StatelessWidget {
  final List<Club> clubs;
  final Set<String> favoriteIds;
  final _ClubFavoriteToggle? onFavoriteToggle;

  const _NearbyNewClubsSheet({
    required this.clubs,
    required this.favoriteIds,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7F1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.near_me_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내 주변 새 클럽',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '반경 5km · 최근 7일 안에 생성된 클럽',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (clubs.isEmpty)
                Expanded(
                  child: Center(
                    child: AppEmptyState(
                      icon: Icons.groups_2_rounded,
                      title: '새로 생긴 클럽이 없습니다',
                      description: '관심 조건을 바꾸거나 조금 뒤에 다시 확인해보세요.',
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: clubs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final club = clubs[index];
                      return _NearbyNewClubCard(
                        club: club,
                        isFavorite: favoriteIds.contains(club.id),
                        onFavoriteToggle: onFavoriteToggle,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyNewClubCard extends StatelessWidget {
  final Club club;
  final bool isFavorite;
  final _ClubFavoriteToggle? onFavoriteToggle;

  const _NearbyNewClubCard({
    required this.club,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final createdAt = club.createdAt;
    final daysAgo =
        createdAt == null ? null : DateTime.now().difference(createdAt).inDays;
    final createdLabel = daysAgo == null
        ? '최근 생성'
        : daysAgo == 0
            ? '오늘 생성'
            : '$daysAgo일 전 생성';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          _SimpleClubAvatar(club: club, size: 64),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F7C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'NEW',
                        style: tt.labelSmall?.copyWith(
                          color: const Color(0xFF4F8F00),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      createdLabel,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  club.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  club.description ?? '새로 등록된 클럽입니다.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniInfoChip(
                      icon: club.sport == 'futsal'
                          ? Icons.sports_soccer_rounded
                          : Icons.sports_tennis_rounded,
                      label: sportLabelFromString(club.sport),
                    ),
                    _MiniInfoChip(
                      icon: Icons.place_rounded,
                      label: club.region ?? '지역 미정',
                    ),
                    _MiniInfoChip(
                      icon: Icons.groups_rounded,
                      label: '멤버 ${club.memberCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
            onPressed: onFavoriteToggle == null
                ? null
                : () => onFavoriteToggle!(club, isFavorite),
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
            color: isFavorite ? cs.primary : cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SimpleClubMiniTile extends StatelessWidget {
  final Club club;
  final bool isFavorite;
  final _ClubFavoriteToggle? onFavoriteToggle;

  const _SimpleClubMiniTile({
    required this.club,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        _SimpleClubAvatar(club: club, size: 52),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
          onPressed: onFavoriteToggle == null
              ? null
              : () => onFavoriteToggle!(club, isFavorite),
          icon: Icon(
            isFavorite
                ? Icons.bookmark_rounded
                : Icons.bookmark_outline_rounded,
          ),
          color: isFavorite ? cs.primary : cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _SimpleActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final Color color;
  final VoidCallback? onTap;

  const _SimpleActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary),
                ),
                child: Text(
                  action!,
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _TeamRecruitingBoard extends StatelessWidget {
  final List<_RecruitingPostPreview> posts;
  final bool showOpenOnly;
  final bool canManage;
  final ValueChanged<bool> onShowOpenOnlyChanged;
  final ValueChanged<_RecruitingPostPreview> onClosePost;

  const _TeamRecruitingBoard({
    required this.posts,
    required this.showOpenOnly,
    required this.canManage,
    required this.onShowOpenOnlyChanged,
    required this.onClosePost,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final openCount = posts.where((post) => !post.isClosed).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '팀원모집 글',
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            showOpenOnly ? '모집중인 글만 보고 있어요.' : '모집중 글과 마감글을 함께 보여줘요.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: showOpenOnly,
              label: Text('모집중만 $openCount'),
              onSelected: onShowOpenOnlyChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (posts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                '선택한 관심 종목에 맞는 팀원모집 글이 없습니다.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final post in posts.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _TeamRecruitingPostCard(
                  post: post,
                  canManage: canManage,
                  onClose: () => onClosePost(post),
                ),
              ),
          Text(
            '마감된 글은 일정 시간이 지나면 목록에서 내려가는 흐름으로 설계했습니다.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TeamRecruitingPostCard extends StatelessWidget {
  final _RecruitingPostPreview post;
  final bool canManage;
  final VoidCallback onClose;

  const _TeamRecruitingPostCard({
    required this.post,
    required this.canManage,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isFutsal = post.sport == 'futsal';
    final accent = post.isClosed ? cs.outline : cs.primary;
    final chipColor = post.isClosed
        ? cs.surfaceContainerHighest
        : (isFutsal ? const Color(0xFFE6F7C7) : const Color(0xFFE8EEFF));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isFutsal
                          ? Icons.sports_soccer_rounded
                          : Icons.sports_tennis_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _RecruitingStatusPill(isClosed: post.isClosed),
                            Text(
                              sportLabelFromString(post.sport),
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          post.clubName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (canManage && !post.isClosed) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('마감하기'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MiniInfoChip(icon: Icons.place_rounded, label: post.region),
              _MiniInfoChip(icon: Icons.schedule_rounded, label: post.schedule),
              _MiniInfoChip(icon: Icons.stars_rounded, label: post.grade),
              _MiniInfoChip(icon: Icons.groups_rounded, label: post.countLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${post.place} · ${post.gender} · ${post.age} · ${post.cost}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RecruitingStatusPill extends StatelessWidget {
  final bool isClosed;

  const _RecruitingStatusPill({required this.isClosed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isClosed ? cs.surfaceContainerHighest : const Color(0xFFE6F7C7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isClosed ? '마감' : '모집중',
        style: TextStyle(
          color: isClosed ? cs.onSurfaceVariant : const Color(0xFF4F8F00),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniInfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamRecruitingDraftSheet extends StatefulWidget {
  final List<Club> managedClubs;

  const _TeamRecruitingDraftSheet({required this.managedClubs});

  @override
  State<_TeamRecruitingDraftSheet> createState() =>
      _TeamRecruitingDraftSheetState();
}

class _TeamRecruitingDraftSheetState extends State<_TeamRecruitingDraftSheet> {
  static const _genders = ['무관', '여성', '남성', '혼성'];
  static const _ages = ['무관', '20대', '30대', '40대', '50대 이상'];
  static const _futsalPositions = ['필드·키퍼', '필드', '키퍼'];
  static const _futsalGrades = ['무관', '입문', '초급', '중급', '고급', '선출'];
  static const _tennisGrades = ['무관', '신입', '5부', '4부', '3부', '2부', '1부'];

  late String _selectedClubId = widget.managedClubs.first.id;
  String _gender = _genders.first;
  String _age = _ages.first;
  String _position = _futsalPositions.first;
  String _grade = _futsalGrades.first;
  int _fieldCount = 4;
  int _keeperCount = 1;
  int _tennisCount = 2;

  Club get _selectedClub =>
      widget.managedClubs.firstWhere((club) => club.id == _selectedClubId);

  bool get _isFutsal => _selectedClub.sport == 'futsal';

  List<String> get _gradeOptions => _isFutsal ? _futsalGrades : _tennisGrades;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7F1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '팀원모집 글쓰기',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '운영 중인 클럽 기준으로 모집글을 작성해요.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _selectedClubId,
                decoration: const InputDecoration(
                  labelText: '모집할 클럽',
                  prefixIcon: Icon(Icons.groups_rounded),
                ),
                items: [
                  for (final club in widget.managedClubs)
                    DropdownMenuItem(
                      value: club.id,
                      child: Text(club.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedClubId = value;
                    _grade = _gradeOptions.first;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _RecruitingPreviewClub(club: _selectedClub),
              const SizedBox(height: AppSpacing.lg),
              _RecruitingSection(
                title: '모집 조건',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '성별',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final gender in _genders)
                          ChoiceChip(
                            label: Text(gender),
                            selected: _gender == gender,
                            onSelected: (_) => setState(() {
                              _gender = gender;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '연령',
                      style: tt.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final age in _ages)
                          ChoiceChip(
                            label: Text(age),
                            selected: _age == age,
                            onSelected: (_) => setState(() {
                              _age = age;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _RecruitingSection(
                title: _isFutsal ? '풋살 모집 상세' : '테니스 모집 상세',
                child: _isFutsal
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '포지션',
                            style: tt.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final position in _futsalPositions)
                                ChoiceChip(
                                  label: Text(position),
                                  selected: _position == position,
                                  onSelected: (_) => setState(() {
                                    _position = position;
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _GradeSelector(
                            title: '등급',
                            options: _gradeOptions,
                            selected: _grade,
                            onSelected: (grade) => setState(() {
                              _grade = grade;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _CountStepper(
                                  label: '필드',
                                  value: _fieldCount,
                                  onChanged: (value) => setState(() {
                                    _fieldCount = value;
                                  }),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _CountStepper(
                                  label: '키퍼',
                                  value: _keeperCount,
                                  onChanged: (value) => setState(() {
                                    _keeperCount = value;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GradeSelector(
                            title: '등급',
                            options: _gradeOptions,
                            selected: _grade,
                            onSelected: (grade) => setState(() {
                              _grade = grade;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _CountStepper(
                            label: '모집 인원',
                            value: _tennisCount,
                            onChanged: (value) => setState(() {
                              _tennisCount = value;
                            }),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _RecruitingSection(
                title: '운동 정보',
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: '운동하는 장소',
                        hintText: '예: 광주 북구 풋살파크 A구장',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: '날짜',
                              hintText: '6/22 (토)',
                              prefixIcon: Icon(Icons.calendar_month_rounded),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: '시간',
                              hintText: '19:00',
                              prefixIcon: Icon(Icons.schedule_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.sm),
                    TextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '비용',
                        hintText: '예: 10,000원 또는 무료',
                        prefixIcon: Icon(Icons.payments_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _RecruitingSection(
                title: '상세 내용',
                child: TextField(
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '필요 포지션, 준비물, 경기 수준, 연락 방식 등을 적어주세요.',
                    alignLabelWithHint: true,
                    labelText: '기타 내용',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _OptionalPhotoPicker(),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('팀원모집 글쓰기 UI 미리보기입니다.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('모집글 올리기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecruitingPreviewClub extends StatelessWidget {
  final Club club;

  const _RecruitingPreviewClub({required this.club});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          _SimpleClubAvatar(club: club, size: 54),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  club.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'} · 운영진',
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

class _GradeSelector extends StatelessWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _GradeSelector({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: selected == option,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _CountStepper extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _CountStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: value > 0 ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value명',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap == null ? cs.surfaceContainerHighest : cs.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? cs.onSurfaceVariant : cs.onPrimary,
        ),
      ),
    );
  }
}

class _RecruitingSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _RecruitingSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _OptionalPhotoPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 선택 UI 미리보기입니다.')),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.add_photo_alternate_rounded, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '사진 추가',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '선택 사항 · 경기장 사진이나 팀 이미지를 넣을 수 있어요.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SimpleClubTile extends StatelessWidget {
  final Club? club;
  final bool isFavorite;
  final _ClubFavoriteToggle? onFavoriteToggle;

  const _SimpleClubTile({
    required this.club,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final item = club;

    if (item == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          '관심 있는 클럽을 찾아 가입해보세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return InkWell(
      onTap: () => context.push('/clubs/${item.id}', extra: item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _SimpleClubAvatar(club: item, size: 72),
                if (item.createdAt != null &&
                    DateTime.now().difference(item.createdAt!).inDays <= 7)
                  Positioned(
                    left: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B4F),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        'N',
                        style: tt.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description ?? '새로운 클럽 일정을 확인해보세요.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sportLabelFromString(item.sport)} · ${item.region ?? '지역 미정'} · 멤버 ${item.memberCount}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
              onPressed: onFavoriteToggle == null
                  ? null
                  : () => onFavoriteToggle!(item, isFavorite),
              icon: Icon(
                isFavorite
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
              ),
              color: isFavorite ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleClubAvatar extends StatelessWidget {
  final Club club;
  final double size;

  const _SimpleClubAvatar({
    required this.club,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _clubLogoSpec(club);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        spec.icon,
        color: spec.foreground,
        size: size * 0.48,
      ),
    );
  }

  _ClubLogoSpec _clubLogoSpec(Club club) {
    final name = club.name;
    if (name.contains('리얼')) {
      return const _ClubLogoSpec(
        icon: Icons.shield_rounded,
        background: Color(0xFFE8F2FF),
        foreground: Color(0xFF2563EB),
      );
    }
    if (name.contains('올라운드')) {
      return const _ClubLogoSpec(
        icon: Icons.all_inclusive_rounded,
        background: Color(0xFFEAF7F1),
        foreground: Color(0xFF059669),
      );
    }
    if (name.contains('위너스')) {
      return const _ClubLogoSpec(
        icon: Icons.emoji_events_rounded,
        background: Color(0xFFFFF4D6),
        foreground: Color(0xFFF59E0B),
      );
    }
    if (name.contains('랠리')) {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    if (name.contains('첨단')) {
      return const _ClubLogoSpec(
        icon: Icons.bolt_rounded,
        background: Color(0xFFEDE9FE),
        foreground: Color(0xFF7C3AED),
      );
    }
    if (name.contains('주말')) {
      return const _ClubLogoSpec(
        icon: Icons.wb_sunny_rounded,
        background: Color(0xFFFFF7ED),
        foreground: Color(0xFFEA580C),
      );
    }
    if (club.sport == 'tennis') {
      return const _ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    return const _ClubLogoSpec(
      icon: Icons.sports_soccer_rounded,
      background: Color(0xFFE8F6D6),
      foreground: Color(0xFF7DCD18),
    );
  }
}

class _ClubLogoSpec {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _ClubLogoSpec({
    required this.icon,
    required this.background,
    required this.foreground,
  });
}

class _ClubSearchFilters {
  final String? region;
  final String? gender;
  final Set<String> days;
  final RangeValues feeRange;

  const _ClubSearchFilters({
    this.region,
    this.gender,
    this.days = const {},
    this.feeRange = const RangeValues(0, 100000),
  });

  bool get hasActive =>
      region != null ||
      gender != null ||
      days.isNotEmpty ||
      feeRange.start > 0 ||
      feeRange.end < 100000;

  List<String> get labels => [
        if (region != null) region!,
        if (gender != null) gender!,
        for (final day in days) day,
        if (feeRange.start > 0 || feeRange.end < 100000)
          '${_formatFee(feeRange.start)}~${_formatFee(feeRange.end)}',
      ];

  _ClubSearchFilters copyWith({
    String? region,
    bool clearRegion = false,
    String? gender,
    bool clearGender = false,
    Set<String>? days,
    RangeValues? feeRange,
  }) {
    return _ClubSearchFilters(
      region: clearRegion ? null : (region ?? this.region),
      gender: clearGender ? null : (gender ?? this.gender),
      days: days ?? this.days,
      feeRange: feeRange ?? this.feeRange,
    );
  }

  _ClubSearchFilters cleared() => const _ClubSearchFilters();
}

class _ClubFilterResult {
  final _ClubSearchFilters filters;
  final Set<String> interests;

  const _ClubFilterResult({
    required this.filters,
    required this.interests,
  });
}

String _formatFee(double value) {
  final amount = value.round();
  if (amount == 0) return '0원';
  if (amount >= 100000) return '10만원+';
  if (amount % 10000 == 0) return '${amount ~/ 10000}만원';
  return '${amount ~/ 1000}천원';
}

class _InterestSheet extends StatefulWidget {
  final Set<String> initialInterests;

  const _InterestSheet({required this.initialInterests});

  @override
  State<_InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends State<_InterestSheet> {
  late final Set<String> _selected = {...widget.initialInterests};

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '관심사 선택',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SportInterestChip(
                  sport: 'tennis',
                  selected: _selected.contains('tennis'),
                  onTap: _toggleSport,
                ),
                _SportInterestChip(
                  sport: 'futsal',
                  selected: _selected.contains('futsal'),
                  onTap: _toggleSport,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('적용하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSport(String sport) {
    setState(() {
      if (!_selected.add(sport)) _selected.remove(sport);
    });
  }
}

class _SportInterestChip extends StatelessWidget {
  final String sport;
  final bool selected;
  final ValueChanged<String> onTap;

  const _SportInterestChip({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';
    final cs = Theme.of(context).colorScheme;

    return FilterChip(
      avatar: Icon(
        isTennis ? Icons.sports_tennis_rounded : Icons.sports_soccer_rounded,
        size: 18,
      ),
      showCheckmark: true,
      checkmarkColor: cs.primary,
      selectedColor: cs.primaryContainer,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
      ),
      label: Text(sportLabelFromString(sport)),
      labelStyle: TextStyle(
        color: selected ? cs.primary : cs.onSurface,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
      ),
      selected: selected,
      onSelected: (_) => onTap(sport),
    );
  }
}

class _ClubFilterSheet extends StatefulWidget {
  final _ClubSearchFilters initialFilters;
  final Set<String> initialInterests;
  final String title;
  final IconData icon;
  final Color accentColor;
  final Color onAccentColor;

  const _ClubFilterSheet({
    required this.initialFilters,
    required this.initialInterests,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onAccentColor,
  });

  @override
  State<_ClubFilterSheet> createState() => _ClubFilterSheetState();
}

class _ClubFilterSheetState extends State<_ClubFilterSheet> {
  static const _regions = ['서울', '경기', '인천', '광주', '부산', '대구', '대전'];
  static const _genders = ['여성', '남성', '혼성'];
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  late _ClubSearchFilters _filters = widget.initialFilters;
  late Set<String> _selectedInterests = widget.initialInterests.isEmpty
      ? const {'tennis', 'futsal'}
      : {...widget.initialInterests};

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.onAccentColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.title,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _FilterSection(
              title: '종목',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SportInterestChip(
                      sport: 'tennis',
                      selected: _selectedInterests.contains('tennis'),
                      onTap: _selectSport,
                    ),
                    _SportInterestChip(
                      sport: 'futsal',
                      selected: _selectedInterests.contains('futsal'),
                      onTap: _selectSport,
                    ),
                  ],
                ),
              ],
            ),
            _FilterSection(
              title: '지역',
              children: [
                _FilterChipWrap(
                  values: _regions,
                  selected: {_filters.region}.whereType<String>().toSet(),
                  onSelected: (value) => setState(() {
                    _filters = _filters.region == value
                        ? _filters.copyWith(clearRegion: true)
                        : _filters.copyWith(region: value);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title: '성별',
              children: [
                _FilterChipWrap(
                  values: _genders,
                  selected: {_filters.gender}.whereType<String>().toSet(),
                  onSelected: (value) => setState(() {
                    _filters = _filters.gender == value
                        ? _filters.copyWith(clearGender: true)
                        : _filters.copyWith(gender: value);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title: '모임요일',
              children: [
                _FilterChipWrap(
                  values: _days,
                  selected: _filters.days,
                  onSelected: (value) => setState(() {
                    final next = {..._filters.days};
                    if (!next.add(value)) next.remove(value);
                    _filters = _filters.copyWith(days: next);
                  }),
                ),
              ],
            ),
            _FilterSection(
              title:
                  '월회비 ${_formatFee(_filters.feeRange.start)} ~ ${_formatFee(_filters.feeRange.end)}',
              children: [
                RangeSlider(
                  values: _filters.feeRange,
                  min: 0,
                  max: 100000,
                  divisions: 20,
                  labels: RangeLabels(
                    _formatFee(_filters.feeRange.start),
                    _formatFee(_filters.feeRange.end),
                  ),
                  onChanged: (value) => setState(() {
                    _filters = _filters.copyWith(feeRange: value);
                  }),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _filters = _filters.cleared();
                      _selectedInterests = widget.initialInterests.isEmpty
                          ? const {'tennis'}
                          : {...widget.initialInterests};
                    }),
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ClubFilterResult(
                        filters: _filters,
                        interests: _selectedInterests,
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('조건 적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectSport(String sport) {
    setState(() {
      _selectedInterests = {sport};
    });
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FilterSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _FilterChipWrap extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onSelected;

  const _FilterChipWrap({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          FilterChip(
            label: Text(value),
            selected: selected.contains(value),
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}
