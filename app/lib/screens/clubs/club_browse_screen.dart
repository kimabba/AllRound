import 'package:flutter/material.dart';

import '../../models/club_recruiting.dart';
import '../../models/tournament.dart';
import '../../theme/tokens.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/clubs/club_filter_widgets.dart';
import '../../widgets/clubs/club_tiles.dart';
import '../../widgets/clubs/team_recruiting_widgets.dart';

class ClubBrowseScreen extends StatefulWidget {
  const ClubBrowseScreen({
    super.key,
    required this.clubs,
    required this.recruitingPosts,
    required this.recruitingCapped,
    required this.initialSports,
    required this.favoriteClubIds,
    required this.managedClubIds,
    required this.openRecruitingClubIds,
    required this.onOpenClub,
    required this.onFavoriteToggle,
    required this.onOpenPost,
    required this.onClosePost,
  });

  final List<Club> clubs;
  final List<RecruitingPostPreview> recruitingPosts;
  final bool recruitingCapped;
  final Set<String> initialSports;
  final Set<String> favoriteClubIds;
  final Set<String> managedClubIds;
  final Set<String> openRecruitingClubIds;
  final ValueChanged<Club> onOpenClub;
  final ClubFavoriteToggle onFavoriteToggle;
  final ValueChanged<RecruitingPostPreview> onOpenPost;
  final Future<List<RecruitingPostPreview>> Function(RecruitingPostPreview)
      onClosePost;

  @override
  State<ClubBrowseScreen> createState() => _ClubBrowseScreenState();
}

class _ClubBrowseScreenState extends State<ClubBrowseScreen> {
  late final TextEditingController _searchController = TextEditingController();
  late Set<String> _sports = {...widget.initialSports};
  late final Set<String> _favoriteClubIds = {...widget.favoriteClubIds};
  late List<RecruitingPostPreview> _recruitingPosts = widget.recruitingPosts;
  ClubSearchFilters _filters = const ClubSearchFilters();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final cs = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<ClubFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ClubFilterSheet(
        initialFilters: _filters,
        initialInterests: _sports,
        initialNameQuery: _query,
        title: '클럽 전체 필터',
        icon: Icons.tune_rounded,
        accentColor: cs.primaryContainer,
        onAccentColor: cs.onPrimaryContainer,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filters = result.filters;
      _sports = {...result.interests};
      _query = result.nameQuery;
      _searchController.text = result.nameQuery;
    });
  }

  void _clearFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _filters = const ClubSearchFilters();
      _sports = {...widget.initialSports};
      _query = '';
      _searchController.clear();
    });
  }

  bool _matchesQuery(Iterable<String?> values) {
    final tokens = _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty);
    if (tokens.isEmpty) return true;
    final haystack = values.whereType<String>().join(' ').toLowerCase();
    return tokens.every(haystack.contains);
  }

  bool _matchesClub(Club club) {
    if (!_sports.contains(club.sport)) return false;
    if (!_matchesQuery([club.name, club.description, club.region])) {
      return false;
    }
    if (_filters.region != null &&
        !clubRegionMatches(club.region, _filters.region!)) {
      return false;
    }
    if (_filters.gender != null &&
        !clubGenderMatches(club.genderPreference, _filters.gender!)) {
      return false;
    }
    if (!clubDaysMatch(club.meetingDays, _filters.days)) return false;
    if (club.monthlyFee != null &&
        (club.monthlyFee! < _filters.feeRange.start ||
            club.monthlyFee! > _filters.feeRange.end)) {
      return false;
    }
    if (_filters.recruitingOnly &&
        !widget.openRecruitingClubIds.contains(club.id)) {
      return false;
    }
    return true;
  }

  bool _matchesRecruitingPost(
    RecruitingPostPreview post,
    Map<String, Club> clubsById,
  ) {
    if (!_sports.contains(post.sport)) return false;
    if (!_matchesQuery([
      post.title,
      post.clubName,
      post.region,
      post.grade,
      post.age,
      post.gender,
    ])) {
      return false;
    }
    if (_filters.recruitingOnly && post.isClosed) return false;
    if (_filters.region != null &&
        !clubRegionMatches(post.region, _filters.region!)) {
      return false;
    }
    if (_filters.gender != null &&
        !clubGenderMatches(post.gender, _filters.gender!)) {
      return false;
    }
    final club = clubsById[post.clubId];
    if (club != null) {
      if (!clubDaysMatch(club.meetingDays, _filters.days)) return false;
      if (club.monthlyFee != null &&
          (club.monthlyFee! < _filters.feeRange.start ||
              club.monthlyFee! > _filters.feeRange.end)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _toggleFavorite(Club club) async {
    final wasFavorite = _favoriteClubIds.contains(club.id);
    setState(() {
      if (wasFavorite) {
        _favoriteClubIds.remove(club.id);
      } else {
        _favoriteClubIds.add(club.id);
      }
    });
    try {
      await widget.onFavoriteToggle(club, wasFavorite);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteClubIds.add(club.id);
        } else {
          _favoriteClubIds.remove(club.id);
        }
      });
    }
  }

  Future<void> _closePost(RecruitingPostPreview post) async {
    final updated = await widget.onClosePost(post);
    if (!mounted) return;
    setState(() => _recruitingPosts = updated);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clubsById = {for (final club in widget.clubs) club.id: club};
    final clubs = widget.clubs.where(_matchesClub).toList()
      ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
    final posts = _recruitingPosts
        .where((post) => _matchesRecruitingPost(post, clubsById))
        .toList();
    final filterLabels = [
      ..._filters.labels,
      if (_sports.length == 1) sportLabelFromString(_sports.single),
    ];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackLocation: '/clubs'),
          title: const Text('전체보기'),
          bottom: TabBar(
            tabs: [
              Tab(text: '클럽 ${clubs.length}'),
              Tab(text: '팀원 모집 ${posts.length}'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      hintText: '클럽·팀원 모집 검색',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: '지역·종목·조건 필터',
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ),
                  ),
                  if (filterLabels.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final label in filterLabels) ...[
                                  Chip(label: Text(label)),
                                  const SizedBox(width: AppSpacing.xs),
                                ],
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('초기화'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: TabBarView(
                children: [
                  _ClubResultsTab(
                    clubs: clubs,
                    favoriteClubIds: _favoriteClubIds,
                    onOpen: widget.onOpenClub,
                    onFavoriteToggle: _toggleFavorite,
                  ),
                  _RecruitingResultsTab(
                    posts: posts,
                    capped: widget.recruitingCapped,
                    managedClubIds: widget.managedClubIds,
                    onOpen: widget.onOpenPost,
                    onClose: _closePost,
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

class _ClubResultsTab extends StatelessWidget {
  const _ClubResultsTab({
    required this.clubs,
    required this.favoriteClubIds,
    required this.onOpen,
    required this.onFavoriteToggle,
  });

  final List<Club> clubs;
  final Set<String> favoriteClubIds;
  final ValueChanged<Club> onOpen;
  final ValueChanged<Club> onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    if (clubs.isEmpty) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.search_off_rounded,
          title: '조건에 맞는 클럽이 없어요',
          description: '검색어나 필터를 조정해보세요.',
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      itemCount: clubs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final club = clubs[index];
        final isFavorite = favoriteClubIds.contains(club.id);
        return _ClubBrowseRow(
          club: club,
          isFavorite: isFavorite,
          onOpen: () => onOpen(club),
          onFavoriteToggle: () => onFavoriteToggle(club),
        );
      },
    );
  }
}

class _ClubBrowseRow extends StatelessWidget {
  const _ClubBrowseRow({
    required this.club,
    required this.isFavorite,
    required this.onOpen,
    required this.onFavoriteToggle,
  });

  final Club club;
  final bool isFavorite;
  final VoidCallback onOpen;
  final VoidCallback onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Row(
          children: [
            SimpleClubAvatar(club: club, size: 48, circular: true),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    club.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    clubRegionMemberLabel(club.region, club.memberCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
              onPressed: onFavoriteToggle,
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              color: isFavorite ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecruitingResultsTab extends StatelessWidget {
  const _RecruitingResultsTab({
    required this.posts,
    required this.capped,
    required this.managedClubIds,
    required this.onOpen,
    required this.onClose,
  });

  final List<RecruitingPostPreview> posts;
  final bool capped;
  final Set<String> managedClubIds;
  final ValueChanged<RecruitingPostPreview> onOpen;
  final ValueChanged<RecruitingPostPreview> onClose;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.person_search_rounded,
          title: '조건에 맞는 모집글이 없어요',
          description: '검색어나 필터를 조정해보세요.',
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      itemCount: posts.length + (capped ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              '최신 등록순 · ${posts.length}개 (최신 글만 표시)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        final post = posts[index];
        return TeamRecruitingPostCard(
          post: post,
          canManage: managedClubIds.contains(post.clubId),
          onClose: () => onClose(post),
          onTap: () => onOpen(post),
        );
      },
    );
  }
}
