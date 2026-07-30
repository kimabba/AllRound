import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/club_recruiting.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/club_labels.dart';
import '../utils/club_sort.dart';
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
  List<Club>? _nearbyClubs;
  bool _loadingNearby = false;
  double _nearbyRadiusKm = 5;
  String? _nearbyError;
  String? _nearbyNotice;

  // 내 클럽 탭
  List<Club>? _myClubs;
  List<Club> _pendingClubs = const <Club>[];
  bool _loadingMy = false;

  // 클럽 찾기 탭
  List<Club>? _clubs;
  bool _loading = false;
  String? _searchError;
  String _clubNameQuery = '';
  late final TextEditingController _clubNameQueryController;
  ClubSearchFilters _clubFilters = const ClubSearchFilters();
  late Set<String> _clubInterests;
  bool _showAllClubs = false;
  ClubSortOrder _clubSortOrder = ClubSortOrder.recommended;
  List<RecruitingPostPreview> _recruitingPosts = const [];
  bool _loadingRecruiting = false;

  /// 모집글 조회 상한. 상한에 닿으면 "전체 보기"가 전부가 아니므로
  /// 화면 하단에 그 사실을 표시한다(_recruitingCapped).
  static const int _recruitingFetchLimit = 200;
  bool _recruitingCapped = false;

  @override
  void initState() {
    super.initState();
    _clubNameQueryController = TextEditingController();
    _clubInterests = {ref.read(activeSportProvider) ?? 'futsal'};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
      _loadRecruitingPosts();
      _restoreClubSortOrder();
    });
  }

  @override
  void dispose() {
    _clubNameQueryController.dispose();
    super.dispose();
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
      final posts = await ref
          .read(apiProvider)
          .teamRecruitingPosts(limit: _recruitingFetchLimit);
      if (mounted) {
        setState(() {
          _recruitingPosts = posts;
          _recruitingCapped = posts.length >= _recruitingFetchLimit;
        });
      }
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
        _clubNameQueryController.text = result.nameQuery;
      });
      _load();
    }
  }

  Future<void> _findNearbyClubs() async {
    setState(() {
      _loadingNearby = true;
      _nearbyError = null;
      _nearbyNotice = null;
    });

    if (AppConfig.userDesignPreview) {
      setState(() {
        _nearbyClubs = _previewClubs.take(4).toList();
        _nearbyNotice = '디자인 미리보기용 주변 클럽입니다.';
        _loadingNearby = false;
      });
      return;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw _NearbyLocationException(
          defaultTargetPlatform == TargetPlatform.iOS
              ? '아이폰 설정에서 위치 서비스를 켜주세요.'
              : '기기 설정에서 위치 서비스를 켜주세요.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _NearbyLocationException(
          '위치 권한을 허용하면 가까운 클럽을 찾을 수 있어요.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw _NearbyLocationException(
          defaultTargetPlatform == TargetPlatform.iOS
              ? '설정 > 개인정보 보호 및 보안 > 위치 서비스에서 올라운드 권한을 허용해주세요.'
              : '기기 설정 > 앱 권한에서 올라운드의 위치 권한을 허용해주세요.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final api = ref.read(apiProvider);
      final sports = _clubInterests.isEmpty
          ? const <String>['tennis', 'futsal']
          : _clubInterests.toList();
      final preciseResults = await Future.wait(
        sports.map(
          (sport) => api.searchClubs(
            sport: sport,
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: _nearbyRadiusKm,
          ),
        ),
      );
      final precise = _dedupeClubs(preciseResults.expand((items) => items))
        ..sort(
          (a, b) => (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity),
        );

      var nearby = precise;
      String? notice;
      // 좌표가 없는 기존 클럽은 거리 계산에서 통째로 빠진다. 정확 결과가 하나라도
      // 있으면 지역 보완을 건너뛰던 예전 로직은 같은 반경의 기존 클럽을 모두
      // 누락시켰다 → 항상 지역 결과를 뒤에 덧붙인다(중복은 제거).
      // geocoding 패키지는 웹을 지원하지 않으므로 웹에서는 건너뛴다.
      if (!kIsWeb) {
        try {
          final placemarks = await Geocoding().placemarkFromCoordinates(
            position.latitude,
            position.longitude,
            locale: const Locale('ko', 'KR'),
          );
          final region = placemarks.isEmpty
              ? null
              : _preferredRegionName(placemarks.first);
          if (region != null) {
            final regionResults = await Future.wait(
              sports.map(
                (sport) => api.searchClubs(sport: sport, region: region),
              ),
            );
            final merged = _dedupeClubs(
              [...precise, ...regionResults.expand((items) => items)],
            );
            final added = merged.length - precise.length;
            if (added > 0) {
              notice = precise.isEmpty
                  ? '거리 정보가 등록된 클럽이 없어 $region 지역 클럽을 보여드려요.'
                  : '거리 정보가 없는 $region 지역 클럽 $added곳도 함께 보여드려요.';
              nearby = merged;
            }
          }
        } catch (error) {
          // 지역 보완 실패가 이미 찾은 정확 결과까지 날리면 안 된다.
          debugPrint('nearby region fallback error: $error');
        }
      }

      if (!mounted) return;
      setState(() {
        _nearbyClubs = nearby;
        _nearbyNotice = notice;
      });
    } on _NearbyLocationException catch (error) {
      if (mounted) setState(() => _nearbyError = error.message);
    } catch (error) {
      debugPrint('nearby clubs error: $error');
      if (mounted) {
        setState(() => _nearbyError = '현재 위치를 확인하지 못했습니다. 지역으로 찾아보세요.');
      }
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  List<Club> _dedupeClubs(Iterable<Club> source) {
    final seen = <String>{};
    return [
      for (final club in source)
        if (seen.add(club.id)) club
    ];
  }

  String? _preferredRegionName(Placemark placemark) {
    for (final value in [
      placemark.administrativeArea,
      placemark.locality,
      placemark.subAdministrativeArea,
    ]) {
      final region = value?.trim();
      if (region != null && region.isNotEmpty) {
        const regionAliases = {
          '서울특별시': '서울',
          '부산광역시': '부산',
          '대구광역시': '대구',
          '인천광역시': '인천',
          '광주광역시': '광주',
          '대전광역시': '대전',
          '울산광역시': '울산',
          '세종특별자치시': '세종',
          '경기도': '경기',
          '충청북도': '충북',
          '충청남도': '충남',
          '전라북도': '전북',
          '전라남도': '전남',
          '경상북도': '경북',
          '경상남도': '경남',
          '강원도': '강원',
          '제주특별자치도': '제주',
          '강원특별자치도': '강원',
          '전북특별자치도': '전북',
          'Seoul': '서울',
        };
        return regionAliases[region] ?? region;
      }
    }
    return null;
  }

  Widget _buildClubFilterControls(bool hasClubNameQuery) {
    final cs = Theme.of(context).colorScheme;
    final labels = <String>[
      if (hasClubNameQuery) _clubNameQuery.trim(),
      ..._clubFilters.labels,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _clubNameQueryController,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '지역이나 클럽 이름 검색',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) {
            setState(() => _clubNameQuery = value.trim());
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<ClubSortOrder>(
                initialValue: _clubSortOrder,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openClubFilterSheet,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('지역·요일·조건'),
              ),
            ),
          ],
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final label in labels)
                Chip(
                  backgroundColor: cs.primaryContainer,
                  label: Text(label),
                ),
              ActionChip(
                avatar: const Icon(Icons.close_rounded, size: 16),
                label: const Text('초기화'),
                onPressed: () {
                  setState(() {
                    _clubNameQuery = '';
                    _clubNameQueryController.clear();
                    _clubFilters = const ClubSearchFilters();
                  });
                },
              ),
            ],
          ),
        ],
      ],
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

  Future<void> _openAllRecruitingPosts(
    List<RecruitingPostPreview> posts,
    Set<String> managedClubIds,
  ) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamRecruitingListScreen(
          posts: posts,
          managedClubIds: managedClubIds,
          capped: _recruitingCapped,
          onClosePost: _closeRecruitingPost,
          onOpenPost: _openRecruitingDetail,
        ),
      ),
    );
  }

  /// 마감 후 갱신된 목록을 돌려준다. 전체보기 화면은 스냅샷을 들고 있어서
  /// 이 반환값으로 자기 목록을 갱신해야 마감 상태가 화면에 반영된다.
  Future<List<RecruitingPostPreview>> _closeRecruitingPost(
    RecruitingPostPreview post,
  ) async {
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
    if (confirmed != true) return _visibleRecruitingPosts();

    try {
      await ref.read(apiProvider).closeTeamRecruitingPost(post.id);
      await _loadRecruitingPosts();
      if (!mounted) return _visibleRecruitingPosts();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀원 모집을 마감했습니다.')),
      );
    } catch (_) {
      if (!mounted) return _visibleRecruitingPosts();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집을 마감하지 못했습니다.')),
      );
    }
    return _visibleRecruitingPosts();
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
        .where(
          (club) =>
              !_clubFilters.recruitingOnly ||
              _openRecruitingClubIds.contains(club.id),
        )
        .toList();
    final hasClubNameQuery = _clubNameQuery.trim().isNotEmpty;
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
          const ProfileAction(),
          TextButton.icon(
            onPressed: _openCreate,
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
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
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.42),
                      borderRadius: AppRadius.card,
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SimpleSectionHeader(
                          title: '나의 클럽',
                          subtitle: '내가 참여하고 있는 클럽',
                          icon: Icons.verified_rounded,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(
                              '참여 중 ${joinedClubs.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_loadingMy)
                          const LinearProgressIndicator()
                        else if (joinedClubs.isEmpty && pendingClubs.isEmpty)
                          SimpleClubTile(
                            club: null,
                            onFavoriteToggle: _toggleClubFavorite,
                          )
                        else ...[
                          for (final club in pendingClubs)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: SimpleClubTile(
                                club: club,
                                pending: true,
                                isMyClub: true,
                                backgroundColor: cs.surface,
                                isFavorite: favoriteClubIds.contains(club.id),
                                onFavoriteToggle: _toggleClubFavorite,
                                onOpen: () => _openClub(club),
                              ),
                            ),
                          for (final club in joinedClubs)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: SimpleClubTile(
                                club: club,
                                isMyClub: true,
                                backgroundColor: cs.surface,
                                isFavorite: favoriteClubIds.contains(club.id),
                                onFavoriteToggle: _toggleClubFavorite,
                                onOpen: () => _openClub(club),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildClubFilterControls(hasClubNameQuery),
                  const SizedBox(height: AppSpacing.lg),
                  SimpleSectionHeader(
                    title: hasClubNameQuery ? '검색 결과' : '추천 클럽',
                    icon: hasClubNameQuery
                        ? Icons.search_rounded
                        : Icons.explore_outlined,
                    subtitle: hasClubNameQuery
                        ? '"${_clubNameQuery.trim()}"'
                        : (_clubFilters.hasActive
                            ? _clubFilters.labels.join(' · ')
                            // 이 분기는 필터가 없는 상태 = region null 이라 지역을
                            // 반영하지 않는다. 지역까지 쓰려면 필터를 걸어야 한다.
                            : '관심 종목을 기준으로 추천해요'),
                    trailing: Text('${recommendedClubs.length}개'),
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
                          backgroundColor: cs.surfaceContainerLowest,
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
                  const SizedBox(height: AppSpacing.lg),
                  SimplePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SimpleSectionHeader(
                          title: '내 주변 클럽',
                          subtitle: '버튼을 누를 때 현재 위치를 한 번만 확인해요',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SegmentedButton<double>(
                          segments: const [
                            ButtonSegment(value: 3, label: Text('3km')),
                            ButtonSegment(value: 5, label: Text('5km')),
                            ButtonSegment(value: 10, label: Text('10km')),
                          ],
                          selected: {_nearbyRadiusKm},
                          onSelectionChanged: _loadingNearby
                              ? null
                              : (values) {
                                  setState(() {
                                    _nearbyRadiusKm = values.first;
                                    _nearbyClubs = null;
                                    _nearbyNotice = null;
                                  });
                                },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed:
                                    _loadingNearby ? null : _findNearbyClubs,
                                icon: const Icon(Icons.my_location_rounded),
                                label: Text(
                                  _loadingNearby ? '찾는 중...' : '내 위치로 찾기',
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openClubFilterSheet,
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('지역 직접 선택'),
                              ),
                            ),
                          ],
                        ),
                        if (_loadingNearby) ...[
                          const SizedBox(height: AppSpacing.md),
                          const LinearProgressIndicator(),
                        ],
                        if (_nearbyError != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _nearbyError!,
                            style: TextStyle(color: cs.error),
                          ),
                        ],
                        if (_nearbyNotice != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _nearbyNotice!,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                        if (_nearbyClubs != null && !_loadingNearby) ...[
                          const SizedBox(height: AppSpacing.md),
                          if (_nearbyClubs!.isEmpty)
                            const AppEmptyState(
                              icon: Icons.location_off_outlined,
                              title: '주변 클럽을 찾지 못했어요',
                              description: '반경을 넓히거나 지역을 직접 선택해보세요.',
                            )
                          else ...[
                            for (final club in _nearbyClubs!.take(4))
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: SimpleClubTile(
                                  club: club,
                                  backgroundColor: cs.surfaceContainerLowest,
                                  isFavorite: favoriteClubIds.contains(club.id),
                                  onFavoriteToggle: _toggleClubFavorite,
                                  onOpen: () => _openClub(club),
                                ),
                              ),
                            if (_nearbyClubs!.length > 4)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _openNearbyNewClubsSheet(_nearbyClubs!),
                                  child: const Text('주변 클럽 전체 보기'),
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
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
                    isLoading: _loadingRecruiting,
                    managedClubIds: managedClubs.map((club) => club.id).toSet(),
                    onClosePost: _closeRecruitingPost,
                    onOpenPost: _openRecruitingDetail,
                    onViewAll: () => _openAllRecruitingPosts(
                      _visibleRecruitingPosts(),
                      managedClubs.map((club) => club.id).toSet(),
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
        .where((post) => !_clubFilters.recruitingOnly || !post.isClosed)
        .toList(growable: false);
  }

  Set<String> get _openRecruitingClubIds => _recruitingPosts
      .where((post) => !post.isClosed)
      .map((post) => post.clubId)
      .toSet();
}

class _NearbyLocationException implements Exception {
  final String message;

  const _NearbyLocationException(this.message);
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
