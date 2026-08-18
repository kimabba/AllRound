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
import '../utils/club_card_colors.dart';
import '../utils/club_sections.dart';
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
  List<Club>? _nearbyClubs;
  bool _loadingNearby = false;
  final double _nearbyRadiusKm = 5;
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
  late final FocusNode _clubNameQueryFocusNode;
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
    _clubNameQueryFocusNode = FocusNode()
      ..addListener(_handleClubSearchFocusChanged);
    _clubInterests = {ref.read(activeSportProvider) ?? 'futsal'};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
      _loadRecruitingPosts();
      _restoreClubSortOrder();
      if (AppConfig.userDesignPreview) _findNearbyClubs();
    });
  }

  @override
  void dispose() {
    _clubNameQueryFocusNode
      ..removeListener(_handleClubSearchFocusChanged)
      ..dispose();
    _clubNameQueryController.dispose();
    super.dispose();
  }

  void _handleClubSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreClubSortOrder() async {
    final order = await loadClubSortOrder();
    if (mounted) setState(() => _clubSortOrder = order);
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
          (sport) => api.searchClubs(sport: sport, region: _clubFilters.region),
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
    await Future.wait([_loadMyClubs(), _load(), _loadRecruitingPosts()]);
  }

  Future<void> _openCreate() async {
    final selectedSport = _clubInterests.length == 1
        ? _clubInterests.single
        : ref.read(activeSportProvider);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClubCreateScreen(initialSport: selectedSport),
      ),
    );
    if (result == true) {
      ref.invalidate(myClubsProvider);
      _loadMyClubs();
      _load();
    }
  }

  Future<void> _openClubFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
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
        _nearbyClubs = _previewClubs
            .where((club) => _clubInterests.contains(club.sport))
            .take(4)
            .toList();
        _nearbyNotice = AppConfig.appStoreScreenshot
            ? null
            : '디자인 미리보기용 주변 클럽입니다.';
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
        throw const _NearbyLocationException('위치 권한을 허용하면 가까운 클럽을 찾을 수 있어요.');
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
          (a, b) => (a.distanceKm ?? double.infinity).compareTo(
            b.distanceKm ?? double.infinity,
          ),
        );

      var nearby = precise;
      String? notice;
      // 좌표가 없는 기존 모임은 거리 계산에서 통째로 빠진다. 정확 결과가 하나라도
      // 있으면 지역 보완을 건너뛰던 예전 로직은 같은 반경의 기존 모임을 모두
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
            final merged = _dedupeClubs([
              ...precise,
              ...regionResults.expand((items) => items),
            ]);
            final added = merged.length - precise.length;
            if (added > 0) {
              notice = precise.isEmpty
                  ? '거리 정보가 없어 $region 모임을 보여드려요.'
                  : '거리 정보가 없는 $region 모임 $added곳도 보여드려요.';
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
        if (seen.add(club.id)) club,
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
        _ClubSportSelector(
          selectedSports: _clubInterests,
          onSelected: (sport) {
            ref.read(sportOverrideProvider.notifier).select(sport);
            setState(() {
              _clubInterests = {sport};
              _showAllClubs = false;
            });
            _load();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _clubNameQueryController,
          focusNode: _clubNameQueryFocusNode,
          textInputAction: TextInputAction.search,
          onTapOutside: (_) => _clubNameQueryFocusNode.unfocus(),
          decoration: InputDecoration(
            hintText: '지역이나 클럽 이름 검색',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_clubNameQueryFocusNode.hasFocus)
                  IconButton(
                    tooltip: '키보드 닫기',
                    onPressed: _clubNameQueryFocusNode.unfocus,
                    icon: const Icon(Icons.keyboard_hide_rounded),
                  ),
                IconButton(
                  tooltip: '지역·요일·조건 필터',
                  onPressed: _openClubFilterSheet,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          onChanged: (value) {
            setState(() => _clubNameQuery = value.trim());
          },
          onSubmitted: (value) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _clubNameQuery = value.trim());
          },
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final label in labels)
                Chip(backgroundColor: cs.primaryContainer, label: Text(label)),
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

  Widget _buildClubDiscoveryResults({
    required bool hasClubNameQuery,
    required List<Club> recommendedClubs,
    required List<Club> displayedClubs,
    required Set<String> favoriteClubIds,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClubHomeSectionHeader(
          title: hasClubNameQuery
              ? '검색 결과 ${recommendedClubs.length}'
              : '추천 클럽',
          trailingLabel: hasClubNameQuery ? null : '전체보기',
          onTrailingTap: hasClubNameQuery
              ? null
              : () {
                  setState(() {
                    _showAllClubs = !_showAllClubs;
                    if (_showAllClubs) {
                      _clubInterests = {'tennis', 'futsal'};
                    }
                  });
                  if (_showAllClubs) _load();
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading || _loadingMy) const LinearProgressIndicator(),
        if (_searchError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _searchError!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ],
        if (displayedClubs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: AppEmptyState(
              icon: hasClubNameQuery || _clubFilters.hasActive
                  ? Icons.search_off_rounded
                  : Icons.sports_rounded,
              title: hasClubNameQuery || _clubFilters.hasActive
                  ? '조건에 맞는 클럽이 없어요'
                  : '아직 등록된 클럽이 없어요',
              description: hasClubNameQuery || _clubFilters.hasActive
                  ? '검색어를 줄이거나 맞춤 조건을 바꿔보세요.'
                  : '새 클럽을 만들면 이곳에서 다른 사용자에게 소개돼요.',
              actionLabel: hasClubNameQuery || _clubFilters.hasActive
                  ? null
                  : '첫 클럽 만들기',
              onAction: hasClubNameQuery || _clubFilters.hasActive
                  ? null
                  : _openCreate,
            ),
          )
        else if (hasClubNameQuery)
          for (final club in displayedClubs)
            _ClubSearchResultRow(club: club, onOpen: () => _openClub(club))
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: displayedClubs.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final club = displayedClubs[index];
                return _ClubDiscoveryCard(
                  club: club,
                  isFavorite: favoriteClubIds.contains(club.id),
                  onFavoriteToggle: () => _toggleClubFavorite(
                    club,
                    favoriteClubIds.contains(club.id),
                  ),
                  onOpen: () => _openClub(club),
                );
              },
            ),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀원 모집글을 올렸습니다.')));
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
    final candidates = [...?_clubs, ...?_myClubs];
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('클럽 정보를 불러오지 못했습니다.')));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamRecruitingDetailScreen(post: post, club: club),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('팀원 모집을 마감했습니다.')));
    } catch (_) {
      if (!mounted) return _visibleRecruitingPosts();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('모집을 마감하지 못했습니다.')));
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
    final myMembershipClubs = (_myClubs ?? const <Club>[])
        .where((club) => club.isMember)
        .where((club) => _clubInterests.contains(club.sport))
        .toList();
    final joinedClubs = myMembershipClubs
        .where((club) => club.isApproved)
        .toList();
    // 승인 대기 카드 = 내가 만든 승인 대기 클럽(JY-150) + 내가 낸 가입신청.
    final pendingClubs = pendingClubCards(
      myClubs: myMembershipClubs,
      joinRequestClubs: _pendingClubs,
    );
    final managedClubs = joinedClubs.where((club) => club.isManager).toList();
    final visibleRecruitingPosts = _visibleRecruitingPosts();

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
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshClubLists,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  _buildClubFilterControls(hasClubNameQuery),
                  if (hasClubNameQuery) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildClubDiscoveryResults(
                      hasClubNameQuery: true,
                      recommendedClubs: recommendedClubs,
                      displayedClubs: displayedRecommendationClubs,
                      favoriteClubIds: favoriteClubIds,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (joinedClubs.isNotEmpty || pendingClubs.isNotEmpty) ...[
                    _MyClubsCarousel(
                      joinedClubs: joinedClubs,
                      pendingClubs: pendingClubs,
                      onOpen: _openClub,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _buildNearbyClubsSection(favoriteClubIds: favoriteClubIds),
                  const SizedBox(height: AppSpacing.xl),
                  if (_loadingRecruiting ||
                      visibleRecruitingPosts.isNotEmpty ||
                      managedClubs.isNotEmpty) ...[
                    if (managedClubs.isNotEmpty) ...[
                      SimpleActionCard(
                        icon: Icons.person_add_alt_1_rounded,
                        title: '팀원모집',
                        subtitle:
                            '${managedClubs.length}개 운영 클럽에서 모집글을 관리할 수 있어요.',
                        color: cs.secondaryContainer,
                        onTap: () => _openTeamRecruitingSheet(managedClubs),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    TeamRecruitingBoard(
                      posts: visibleRecruitingPosts,
                      isLoading: _loadingRecruiting,
                      managedClubIds: managedClubs
                          .map((club) => club.id)
                          .toSet(),
                      onClosePost: _closeRecruitingPost,
                      onOpenPost: _openRecruitingDetail,
                      onViewAll: () => _openAllRecruitingPosts(
                        visibleRecruitingPosts,
                        managedClubs.map((club) => club.id).toSet(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  if (!hasClubNameQuery)
                    _buildClubDiscoveryResults(
                      hasClubNameQuery: false,
                      recommendedClubs: recommendedClubs,
                      displayedClubs: displayedRecommendationClubs,
                      favoriteClubIds: favoriteClubIds,
                    ),
                  if (!hasClubNameQuery) ...[
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('클럽 만들기'),
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

  Widget _buildNearbyClubsSection({required Set<String> favoriteClubIds}) {
    final cs = Theme.of(context).colorScheme;
    final nearby = _nearbyClubs ?? const <Club>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClubHomeSectionHeader(
          title: '내 주변 클럽',
          trailingLabel: nearby.isEmpty ? null : '전체보기',
          onTrailingTap: nearby.isEmpty
              ? null
              : () => _openNearbyNewClubsSheet(nearby),
        ),
        if (_loadingNearby) ...[
          const SizedBox(height: AppSpacing.sm),
          const LinearProgressIndicator(),
        ],
        if (_nearbyError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_nearbyError!, style: TextStyle(color: cs.error)),
        ],
        if (_nearbyNotice != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _nearbyNotice!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (nearby.isNotEmpty && !_loadingNearby) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: nearby.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final club = nearby[index];
                return _ClubDiscoveryCard(
                  club: club,
                  isFavorite: favoriteClubIds.contains(club.id),
                  onFavoriteToggle: () => _toggleClubFavorite(
                    club,
                    favoriteClubIds.contains(club.id),
                  ),
                  onOpen: () => _openClub(club),
                );
              },
            ),
          ),
        ],
        if (_nearbyClubs != null && nearby.isEmpty && !_loadingNearby) ...[
          const SizedBox(height: AppSpacing.sm),
          const AppEmptyState(
            icon: Icons.location_off_outlined,
            title: '주변 클럽을 찾지 못했어요',
            description: '반경을 넓히거나 지역을 직접 선택해보세요.',
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loadingNearby ? null : _findNearbyClubs,
            icon: const Icon(Icons.my_location_rounded),
            label: Text(_nearbyClubs == null ? '내 위치로 찾기' : '내 위치로 다시 찾기'),
          ),
        ),
      ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('클럽이 삭제되었습니다.')));
    } else if (result == ClubDetailResult.membershipChanged) {
      setState(() {
        _myClubs?.removeWhere((item) => item.id == club.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('클럽에서 탈퇴했습니다.')));
    }

    await _refreshClubLists();
  }

  List<Club> _recommendedClubs(List<Club> source) {
    final scored = [
      for (final club in source)
        (
          club: club,
          score:
              (_clubFilters.region != null &&
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

class _ClubSportSelector extends StatelessWidget {
  const _ClubSportSelector({
    required this.selectedSports,
    required this.onSelected,
  });

  final Set<String> selectedSports;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = selectedSports.contains('tennis') ? 'tennis' : 'futsal';
    final label = sportLabelFromString(selected);
    final icon = selected == 'tennis'
        ? Icons.sports_tennis_rounded
        : Icons.sports_soccer_rounded;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: '주종목 선택',
        initialValue: selected,
        onSelected: onSelected,
        itemBuilder: (_) => [
          PopupMenuItem(value: 'futsal', child: Text(sportLabel(Sport.futsal))),
          PopupMenuItem(value: 'tennis', child: Text(sportLabel(Sport.tennis))),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.primary),
            borderRadius: AppRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '내 주종목  $label',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyClubsCarousel extends StatefulWidget {
  const _MyClubsCarousel({
    required this.joinedClubs,
    required this.pendingClubs,
    required this.onOpen,
  });

  final List<Club> joinedClubs;
  final List<Club> pendingClubs;
  final ValueChanged<Club> onOpen;

  @override
  State<_MyClubsCarousel> createState() => _MyClubsCarouselState();
}

class _MyClubsCarouselState extends State<_MyClubsCarousel> {
  late final PageController _controller = PageController(viewportFraction: .96);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubs = [...widget.pendingClubs, ...widget.joinedClubs];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ClubHomeSectionHeader(title: '나의 클럽'),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 108,
          child: LayoutBuilder(
            builder: (context, constraints) => Transform.translate(
              offset: const Offset(-AppSpacing.md, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: constraints.maxWidth + AppSpacing.xxl,
                maxWidth: constraints.maxWidth + AppSpacing.xxl,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: clubs.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  itemBuilder: (context, index) {
                    final club = clubs[index];
                    final pending = widget.pendingClubs.contains(club);
                    final color = clubCardColor(club.cardColor);
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == clubs.length - 1 ? 0 : AppSpacing.sm,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: AppRadius.hero,
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                color,
                                Color.lerp(color, Colors.black, .18)!,
                              ],
                            ),
                            borderRadius: AppRadius.hero,
                          ),
                          child: InkWell(
                            onTap: () => widget.onOpen(club),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.md,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .94,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: SimpleClubAvatar(
                                      club: club,
                                      size: 48,
                                      circular: true,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          club.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.xs,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: .72),
                                                ),
                                                borderRadius: AppRadius.pill,
                                              ),
                                              child: Text(
                                                pending ? '승인 대기' : '멤버',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Expanded(
                                              child: Text(
                                                clubRegionMemberLabel(
                                                  club.region,
                                                  club.memberCount,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: .88),
                                                  fontWeight: FontWeight.w700,
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
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (clubs.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < clubs.length; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: index == _page ? 10 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
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

class _ClubDiscoveryCard extends StatelessWidget {
  const _ClubDiscoveryCard({
    required this.club,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onOpen,
  });

  final Club club;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imageUrl = club.introImageUrls.isNotEmpty
        ? club.introImageUrls.first.trim()
        : club.logoUrl?.trim();
    return Material(
      color: cs.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          width: 172,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: AppRadius.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 112,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? ColoredBox(
                            color: cs.primaryContainer,
                            child: Center(
                              child: SimpleClubAvatar(club: club, size: 70),
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: cs.primaryContainer,
                              child: Center(
                                child: SimpleClubAvatar(club: club, size: 70),
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: .86),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
                        onPressed: onFavoriteToggle,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        color: isFavorite ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      club.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        clubRegionMemberLabel(club.region, club.memberCount),
                        if (club.distanceKm != null)
                          '${club.distanceKm!.toStringAsFixed(1)}km',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _ClubHomeSectionHeader extends StatelessWidget {
  const _ClubHomeSectionHeader({
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

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
        if (trailingLabel != null)
          TextButton.icon(
            onPressed: onTrailingTap,
            label: Text(trailingLabel!),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
          ),
      ],
    );
  }
}

class _ClubSearchResultRow extends StatelessWidget {
  const _ClubSearchResultRow({required this.club, required this.onOpen});

  final Club club;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SimpleClubAvatar(club: club, size: 48),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
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
    description: '평일 퇴근 후 가볍게 뛰는 직장인 풋살 클럽입니다.',
    memberCount: 16,
    meetingDays: const ['목'],
    monthlyFee: 20000,
    myRole: 'member',
  ),
  Club(
    id: 'preview-club-my-2',
    sport: 'futsal',
    name: '한강 풋살 유나이티드',
    region: '서울',
    address: '서울 마포구 망원동',
    description: '수요일 저녁에 함께 뛰는 직장인 풋살 클럽입니다.',
    memberCount: 18,
    meetingDays: const ['수'],
    monthlyFee: 25000,
    myRole: 'member',
    cardColor: '#E05252',
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
  RecruitingPostPreview(
    id: 'preview-recruiting-2',
    clubId: 'preview-club-futsal-2',
    sport: 'futsal',
    clubName: '한강 풋살 유나이티드',
    title: '평일 저녁 회원 모집',
    region: '서울',
    place: '망원 풋살장',
    schedule: '매주 수요일 20:00',
    grade: '중급',
    gender: '여성',
    age: '30–50대',
    position: '필드',
    fieldCount: 4,
    keeperCount: 0,
    totalCount: 4,
    cost: '월 2.5만원',
    intro: '즐겁게 오래 함께할 팀원을 찾습니다.',
    createdAt: DateTime(2026, 7, 18),
  ),
];
