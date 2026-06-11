import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/matchup_logo.dart';
import 'clubs/club_create_screen.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // 내 클럽 탭
  List<Club>? _myClubs;
  bool _loadingMy = false;

  // 클럽 찾기 탭
  String _q = '';
  List<Club>? _clubs;
  bool _loading = false;
  String? _searchError;
  _ClubSearchFilters _clubFilters = const _ClubSearchFilters();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyClubs();
      _load();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (mounted) setState(() {});
  }

  Future<void> _loadMyClubs() async {
    setState(() => _loadingMy = true);
    try {
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
      final list = await ref.read(apiProvider).searchClubs(
            sport: ref.read(activeSportProvider),
            region: _clubFilters.region,
            q: _q,
          );
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

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _load());
    final sport = ref.watch(activeSportProvider);
    final favoriteIds =
        ref.watch(clubFavoriteIdsProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '클럽'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '내 클럽'),
            Tab(text: '클럽 찾기'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('클럽 만들기'),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MyClubsTab(
            clubs: _myClubs,
            loading: _loadingMy,
            favoriteIds: favoriteIds,
            onRefresh: _loadMyClubs,
          ),
          _SearchTab(
            q: _q,
            sport: sport,
            clubs: _clubs,
            loading: _loading,
            error: _searchError,
            favoriteIds: favoriteIds,
            filters: _clubFilters,
            onQueryChanged: (v) => _q = v,
            onFiltersChanged: (filters) {
              setState(() => _clubFilters = filters);
              _load();
            },
            onSearch: _load,
            onJoined: () {
              _loadMyClubs();
              _load();
            },
          ),
        ],
      ),
    );
  }
}

// ─── 내 클럽 탭 ──────────────────────────────────────────────────────────────

class _MyClubsTab extends ConsumerWidget {
  final List<Club>? clubs;
  final bool loading;
  final Set<String> favoriteIds;
  final VoidCallback onRefresh;

  const _MyClubsTab({
    required this.clubs,
    required this.loading,
    required this.favoriteIds,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading && clubs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (clubs == null || clubs!.isEmpty) {
      return const AppEmptyState(
        icon: Icons.groups_rounded,
        title: '소속 클럽이 없습니다',
        description: '클럽 찾기 탭에서 가입 신청하거나\n클럽 만들기로 새 클럽을 열어보세요.',
      );
    }

    // pending(대기중) 클럽을 맨 위로
    final sorted = [...clubs!]..sort((a, b) {
        if (a.isPending && !b.isPending) return -1;
        if (!a.isPending && b.isPending) return 1;
        return 0;
      });

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        itemCount: sorted.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _ClubCard(
            club: sorted[i],
            showRole: true,
            isFavorite: favoriteIds.contains(sorted[i].id),
            onChanged: onRefresh,
          ),
        ),
      ),
    );
  }
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

String _formatFee(double value) {
  final amount = value.round();
  if (amount == 0) return '0원';
  if (amount >= 100000) return '10만원+';
  if (amount % 10000 == 0) return '${amount ~/ 10000}만원';
  return '${amount ~/ 1000}천원';
}

// ─── 클럽 찾기 탭 ────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  final String q;
  final String? sport;
  final List<Club>? clubs;
  final bool loading;
  final String? error;
  final Set<String> favoriteIds;
  final _ClubSearchFilters filters;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_ClubSearchFilters> onFiltersChanged;
  final VoidCallback onSearch;
  final VoidCallback onJoined;

  const _SearchTab({
    required this.q,
    required this.sport,
    required this.clubs,
    required this.loading,
    this.error,
    required this.favoriteIds,
    required this.filters,
    required this.onQueryChanged,
    required this.onFiltersChanged,
    required this.onSearch,
    required this.onJoined,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = sport == 'tennis';
    final accent = isTennis ? cs.tertiary : cs.secondary;
    final visibleClubs =
        clubs?.where((club) => _matchesClientFilters(club, filters)).toList();

    return Column(
      children: [
        Container(
          color: cs.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openFilterSheet(context),
                  child: Ink(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent,
                          isTennis
                              ? cs.tertiaryContainer
                              : cs.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -8,
                          bottom: -18,
                          child: Icon(
                            isTennis
                                ? Icons.sports_tennis_rounded
                                : Icons.sports_soccer_rounded,
                            size: 96,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '조건 설정',
                                  style: tt.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTennis ? '테니스 클럽 찾기' : '풋살 클럽 찾기',
                              style: tt.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              filters.hasActive
                                  ? filters.labels.join(' · ')
                                  : '지역, 성별, 모임요일, 월회비로 찾아보세요.',
                              style: tt.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (filters.hasActive) ...[
                const SizedBox(height: AppSpacing.sm),
                _ActiveFilterChips(
                  filters: filters,
                  onClear: () => onFiltersChanged(filters.cleared()),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                decoration: InputDecoration(
                  hintText: '클럽명·설명 검색',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                ),
                onChanged: onQueryChanged,
                onSubmitted: (_) => onSearch(),
              ),
            ],
          ),
        ),
        if (loading) LinearProgressIndicator(color: cs.primary),
        Expanded(
          child: error != null
              ? AppEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: error!,
                  description: '네트워크 연결을 확인하고 다시 시도해 주세요.',
                  actionLabel: '다시 시도',
                  onAction: onSearch,
                )
              : clubs == null
                  ? const SizedBox.shrink()
                  : visibleClubs!.isEmpty
                      ? const AppEmptyState(
                          icon: Icons.groups_rounded,
                          title: '등록된 클럽이 없습니다',
                          description: '다른 검색어나 필터로 시도해 보세요.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.lg,
                          ),
                          itemCount: visibleClubs.length,
                          itemBuilder: (_, i) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: _ClubCard(
                              club: visibleClubs[i],
                              showRole: false,
                              isFavorite:
                                  favoriteIds.contains(visibleClubs[i].id),
                              onChanged: onJoined,
                            ),
                          ),
                        ),
        ),
      ],
    );
  }

  bool _matchesClientFilters(Club club, _ClubSearchFilters filters) {
    if (filters.region != null && club.region != filters.region) return false;
    return true;
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final isTennis = sport == 'tennis';
    final result = await showModalBottomSheet<_ClubSearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClubFilterSheet(
        initialFilters: filters,
        title: isTennis ? '테니스 클럽 찾기' : '풋살 클럽 찾기',
        icon: isTennis
            ? Icons.sports_tennis_rounded
            : Icons.sports_soccer_rounded,
        accentColor: isTennis ? cs.tertiaryContainer : cs.secondaryContainer,
        onAccentColor:
            isTennis ? cs.onTertiaryContainer : cs.onSecondaryContainer,
      ),
    );
    if (result != null) onFiltersChanged(result);
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final _ClubSearchFilters filters;
  final VoidCallback onClear;

  const _ActiveFilterChips({
    required this.filters,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in filters.labels)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.primaryContainer,
                      labelStyle: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: onClear,
          child: const Text('초기화'),
        ),
      ],
    );
  }
}

class _ClubFilterSheet extends StatefulWidget {
  final _ClubSearchFilters initialFilters;
  final String title;
  final IconData icon;
  final Color accentColor;
  final Color onAccentColor;

  const _ClubFilterSheet({
    required this.initialFilters,
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
                    }),
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _filters),
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

// ─── 클럽 카드 ──────────────────────────────────────────────────────────────

class _ClubCard extends ConsumerWidget {
  final Club club;
  final bool showRole;
  final bool isFavorite;
  final VoidCallback onChanged;

  const _ClubCard({
    required this.club,
    required this.showRole,
    required this.isFavorite,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accentColor = isTennis ? cs.tertiary : cs.secondary;

    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
      if (club.memberCount > 0) '${club.memberCount}명',
    ].whereType<String>().join(' · ');

    return AppCard(
      onTap: () => _showDetail(context, ref),
      variant: AppCardVariant.elevated,
      child: Row(
        children: [
          _ClubSportThumbnail(
            sport: club.sport,
            accentColor: accentColor,
            logoUrl: club.logoUrl,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        club.name,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (showRole && club.myRole != null)
                      _RoleChip(role: club.myRole!),
                    if (showRole && club.isPending)
                      _StatusChip(label: '승인 대기중', color: Colors.orange),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
            iconSize: 20,
            color: isFavorite ? accentColor : cs.onSurfaceVariant,
            tooltip: isFavorite ? '관심 해제' : '관심 저장',
            onPressed: () async {
              if (AppConfig.userDesignPreview) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('디자인 미리보기용 관심 버튼입니다.')),
                );
                return;
              }
              await ref
                  .read(apiProvider)
                  .toggleClubFavorite(club.id, !isFavorite);
              ref.invalidate(clubFavoriteIdsProvider);
              ref.invalidate(myFavoriteClubsProvider);
            },
          ),
          if (club.website != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              iconSize: 20,
              color: cs.onSurfaceVariant,
              onPressed: () => launchUrl(
                Uri.parse(club.website!),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref) async {
    await context.push('/clubs/${club.id}', extra: club);
    onChanged();
  }
}

class _ClubSportThumbnail extends StatelessWidget {
  const _ClubSportThumbnail({
    required this.sport,
    required this.accentColor,
    this.logoUrl,
  });

  final String sport;
  final Color accentColor;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final isTennis = sport == 'tennis';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 56,
        height: 56,
        child: logoUrl == null || logoUrl!.isEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    isTennis
                        ? 'assets/images/tournaments/tennis-cover.jpg'
                        : 'assets/images/tournaments/futsal-cover.jpg',
                    fit: BoxFit.cover,
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
                  Icon(
                    isTennis
                        ? Icons.sports_tennis_rounded
                        : Icons.sports_soccer_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              )
            : Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: accentColor.withValues(alpha: 0.16),
                  child: Icon(
                    isTennis
                        ? Icons.sports_tennis_rounded
                        : Icons.sports_soccer_rounded,
                    color: accentColor,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      'owner' => '클럽장',
      'manager' => '운영진',
      _ => '멤버',
    };
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
