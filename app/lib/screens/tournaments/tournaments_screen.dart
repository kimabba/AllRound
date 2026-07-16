import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/active_filters.dart';
import '../../utils/grade_labels.dart';
import '../../utils/recent_tournaments.dart';
import '../../utils/tournament_filters.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/notification_bell_action.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/allround_logo.dart';
import '../../widgets/tournament_card.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  bool _onlyMyGrade = false;
  String _q = '';
  String? _regionCode;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _hostOrg;

  /// 부서 선택의 source of truth = 라벨(테니스: 부서 라벨, 풋살: grade 코드).
  /// 코드는 API 호출 시점에 현재 _hostOrg 로 해석한다(협회 제거 시 union 재확장).
  Set<String> _divisionLabels = const {};
  RecruitingStatus _recruitingStatus = RecruitingStatus.all;
  List<Tournament>? _results;
  bool _loading = false;
  bool _usingPreviewData = false;
  String? _error;

  /// null = 전체 목록 모드. 날짜를 선택하면 그 날짜의 대회만 필터.
  DateTime? _selectedDate;
  late DateTime _focusedMonth;
  String? _lastSearchedSport;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isTennis => ref.read(activeSportProvider) == 'tennis';

  /// 현재 _divisionLabels 를 현재 _hostOrg 스코프로 백엔드 코드로 해석.
  /// 테니스: org 있으면 그 협회 코드만, 없으면 전 협회 union.
  /// 풋살: 라벨 Set 이 곧 grade 코드.
  List<String> _resolveDivisionCodes() {
    if (!_isTennis) return _divisionLabels.toList();
    final org = _hostOrg;
    final codes = org == null
        ? tennisCodesForLabels(_divisionLabels)
        : tennisCodesForLabelsInOrg(org, _divisionLabels);
    return codes.toList();
  }

  /// 종목 전환 시 종목 특화 필터(_hostOrg, 부서 라벨)를 초기화한다.
  /// 종목 무관 필터(지역/기간/모집상태/검색어)는 유지.
  void _onSportChanged() {
    final sport = ref.read(activeSportProvider);
    if (sport == _lastSearchedSport) {
      _search();
      return;
    }
    setState(() {
      _hostOrg = null;
      _divisionLabels = const {};
    });
    _search();
  }

  Future<void> _search() async {
    _lastSearchedSport = ref.read(activeSportProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiProvider);
    if (!kReleaseMode && AppConfig.apiBaseUrl.contains('127.0.0.1')) {
      setState(() {
        _results = _previewTournaments(ref.read(activeSportProvider));
        _usingPreviewData = true;
        _loading = false;
      });
      return;
    }

    List<Tournament> res;
    try {
      // 모집 상태는 서버 측 필터(recruiting 쿼리키)로 처리한다.
      res = await api.searchTournaments(
        sport: ref.read(activeSportProvider),
        onlyMyGrade: _onlyMyGrade,
        query: _q,
        regionCode: _regionCode,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        hostOrg: _hostOrg,
        divisionCodes: _resolveDivisionCodes(),
        recruiting: recruitingStatusToParam(_recruitingStatus),
        limit: 100,
      );
    } catch (e) {
      if (!kReleaseMode && mounted) {
        setState(() {
          _results = _previewTournaments(ref.read(activeSportProvider));
          _usingPreviewData = true;
          _error = null;
          _loading = false;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _results = const [];
          _error = _formatSearchError(e);
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _results = res;
        _usingPreviewData = false;
        _loading = false;
      });
    }
  }

  Future<void> _openRecentTournaments() async {
    final userId = ref.read(currentUserProvider)?.id ?? 'guest';
    final store = await RecentTournamentStore.create();
    final entries = store.load(userId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RecentTournamentsSheet(
        entries: entries,
        onClear: () => store.clear(userId),
        onOpen: (entry) {
          context.push('/tournaments/${entry.id}');
        },
      ),
    );
  }

  String _formatSearchError(Object error) {
    final text = error.toString();
    if (text.contains('503') || text.contains('BOOT_ERROR')) {
      return '대회 검색 서버가 아직 준비되지 않았습니다. 로컬 Supabase Edge Function 상태를 확인한 뒤 다시 시도해 주세요.';
    }
    if (text.contains('401') || text.contains('Authorization')) {
      return '로그인 세션을 확인할 수 없습니다. 다시 로그인한 뒤 시도해 주세요.';
    }
    return '대회 목록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(_today.year, _today.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _onSportChanged());
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);
    // 등급·협회 등록이 없으면 홈 목록 = 전체 대회이므로 "내 등급" 배지가 거짓이 된다.
    // 등급 근거가 있을 때만 배지를 노출한다.
    final hasGradeBasis =
        (ref.watch(userSportsProvider).valueOrNull?.isNotEmpty ?? false) ||
            (ref.watch(userTennisOrgsProvider).valueOrNull?.isNotEmpty ??
                false);
    final myGradeIds = hasGradeBasis
        ? (ref
                .watch(homeTournamentsProvider)
                .valueOrNull
                ?.map((t) => t.id)
                .toSet() ??
            const <String>{})
        : const <String>{};

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '대회 · 모집'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: '최근 본 대회',
            onPressed: _openRecentTournaments,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '대회 제보',
            onPressed: () => context.push('/tournaments/submit'),
          ),
          const NotificationBellAction(),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: _buildCalendarFilterControls(cs),
          ),
          _buildActiveFilterChipsRow(cs),
          // 재검색(기존 결과 유지) 중에만 상단 바. 최초 로드는 아래 스켈레톤이 담당.
          if (_loading && _results != null)
            LinearProgressIndicator(color: cs.primary),
          if (_usingPreviewData) const _PreviewDataBanner(),
          Expanded(
            child: _error != null
                ? _TournamentErrorState(message: _error!, onRetry: _search)
                : _results == null
                    ? (_loading
                        ? const _TournamentSkeletonList()
                        : const SizedBox.shrink())
                    : _results!.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.search_off_rounded,
                            title: '검색 결과 없음',
                            description: '다른 검색어나 필터로 시도해 보세요.',
                          )
                        : _TournamentCalendarListView(
                            tournaments: _results!,
                            favoriteIds:
                                favorites.valueOrNull ?? const <String>{},
                            myGradeIds: myGradeIds,
                            focusedMonth: _focusedMonth,
                            selectedDate: _selectedDate,
                            onMonthChanged: (month) => setState(() {
                              _focusedMonth = month;
                              // 다른 달로 넘기면 이전 날짜 필터 해제 —
                              // 캘린더(새 달)와 목록(옛 날짜) 불일치 방지.
                              if (_selectedDate != null &&
                                  (_selectedDate!.year != month.year ||
                                      _selectedDate!.month != month.month)) {
                                _selectedDate = null;
                              }
                            }),
                            // 같은 날짜 재탭 → 필터 해제(전체로).
                            onDateSelected: (date) => setState(() {
                              _selectedDate = (_selectedDate != null &&
                                      _isSameDay(_selectedDate!, date))
                                  ? null
                                  : date;
                            }),
                            onClearDate: () =>
                                setState(() => _selectedDate = null),
                            onSelectNextTournamentDate: (date) => setState(() {
                              _selectedDate = date;
                              _focusedMonth = DateTime(date.year, date.month);
                            }),
                            onTap: (tournament) =>
                                context.push('/tournaments/${tournament.id}'),
                            onFavoriteToggle: (tournament, isFavorite) async {
                              try {
                                await ref.read(apiProvider).toggleFavorite(
                                      tournament.id,
                                      !isFavorite,
                                    );
                                ref.invalidate(favoriteIdsProvider);
                                ref.invalidate(myFavoriteTournamentsProvider);
                                ref.invalidate(myTournamentRecordsProvider);
                                if (!isFavorite && context.mounted) {
                                  AppToast.show(
                                    context,
                                    '관심 대회로 저장했어요. 신청 마감일과 대회 3일 전에 알려드려요.',
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  AppToast.show(
                                    context,
                                    '관심 저장에 실패했어요. 잠시 후 다시 시도해 주세요.',
                                    kind: AppToastKind.error,
                                  );
                                }
                              }
                            },
                          ),
          ),
        ],
      ),
    );
  }

  List<ActiveFilterChipData> get _activeFilterChips => activeFilterChips(
        sport: ref.read(activeSportProvider),
        query: _q,
        regionCode: _regionCode,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        hostOrg: _hostOrg,
        divisionLabels: _divisionLabels,
        recruiting: _recruitingStatus,
        onlyMyGrade: _onlyMyGrade,
        now: DateTime.now(),
      );

  /// 요약 칩의 X → 그 필터만 해제하고 즉시 재검색.
  /// 부서 칩 제거는 라벨 단위(테니스 라벨 / 풋살 grade). 협회 칩 제거는
  /// _hostOrg 만 해제하고 부서 라벨은 보존 → 다음 검색에서 union 재확장.
  void _removeActiveFilter(ActiveFilterChipData chip) {
    setState(() {
      switch (chip.kind) {
        case ActiveFilterKind.query:
          _q = '';
        case ActiveFilterKind.region:
          _regionCode = null;
        case ActiveFilterKind.dateRange:
          _dateFrom = null;
          _dateTo = null;
        case ActiveFilterKind.hostOrg:
          _hostOrg = null;
        case ActiveFilterKind.division:
          final value = chip.value;
          if (value != null) {
            _divisionLabels = _divisionLabels.where((l) => l != value).toSet();
          }
        case ActiveFilterKind.recruiting:
          _recruitingStatus = RecruitingStatus.all;
        case ActiveFilterKind.onlyMyGrade:
          _onlyMyGrade = false;
      }
    });
    _search();
  }

  Widget _buildActiveFilterChipsRow(ColorScheme cs) {
    final chips = _activeFilterChips;
    if (chips.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final chip in chips)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: InputChip(
                  label: Text(chip.label),
                  onDeleted: () => _removeActiveFilter(chip),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  backgroundColor: cs.primaryContainer,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                  labelStyle: tt.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearchSheet(ColorScheme cs) async {
    final result = await showModalBottomSheet<_SearchFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchFilterSheet(
        sport: ref.read(activeSportProvider),
        initial: _SearchFilterResult(
          query: _q,
          onlyMyGrade: _onlyMyGrade,
          regionCode: _regionCode,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          hostOrg: _hostOrg,
          divisionLabels: _divisionLabels,
          recruiting: _recruitingStatus,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _q = result.query;
        _onlyMyGrade = result.onlyMyGrade;
        _regionCode = result.regionCode;
        _dateFrom = result.dateFrom;
        _dateTo = result.dateTo;
        _hostOrg = result.hostOrg;
        _divisionLabels = result.divisionLabels;
        _recruitingStatus = result.recruiting;
      });
      _search();
    }
  }

  Widget _buildCalendarFilterControls(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final activeFilters = <String>[
      if (_onlyMyGrade) '내 등급',
      if (_q.trim().isNotEmpty) '검색어',
      if (_regionCode != null) '지역',
      if (_dateFrom != null || _dateTo != null) '기간',
      if (_hostOrg != null) '협회',
      if (_divisionLabels.isNotEmpty) '부서',
      if (_recruitingStatus != RecruitingStatus.all)
        recruitingStatusLabel(_recruitingStatus),
    ];
    final filterLabel =
        activeFilters.isEmpty ? '전체 대회 기준' : '${activeFilters.join(' · ')} 적용됨';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 19,
                color: activeFilters.isEmpty ? cs.onSurfaceVariant : cs.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  filterLabel,
                  style: tt.labelLarge?.copyWith(
                    color: activeFilters.isEmpty
                        ? cs.onSurfaceVariant
                        : cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openSearchSheet(cs),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('상세검색'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentTournamentsSheet extends StatelessWidget {
  const _RecentTournamentsSheet({
    required this.entries,
    required this.onClear,
    required this.onOpen,
  });

  final List<RecentTournamentEntry> entries;
  final Future<void> Function() onClear;
  final ValueChanged<RecentTournamentEntry> onOpen;

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최근 본 기록을 지울까요?'),
        content: const Text('이 기기에 저장된 최근 본 대회 기록만 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('기록 지우기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onClear();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '최근 본 대회',
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (entries.isNotEmpty)
                    TextButton(
                      onPressed: () => _clear(context),
                      child: const Text('기록 지우기'),
                    ),
                ],
              ),
              Text(
                '최근 확인한 대회를 이 기기에 최대 10개 보관해요.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              if (entries.isEmpty)
                const Expanded(
                  child: AppEmptyState(
                    icon: Icons.history_rounded,
                    title: '최근 본 대회가 없습니다',
                    description: '대회 상세를 확인하면 여기에 바로 모아드려요.',
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final deadline = entry.applicationDeadline;
                      final place = entry.location ?? entry.region;
                      final subtitle = [
                        sportLabelFromString(entry.sport),
                        '${entry.startDate.month}/${entry.startDate.day}',
                        if (place?.trim().isNotEmpty == true) place!.trim(),
                        if (deadline != null)
                          '신청마감 ${deadline.month}/${deadline.day}',
                      ].join(' · ');
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            entry.sport == 'futsal'
                                ? Icons.sports_soccer_rounded
                                : Icons.sports_tennis_rounded,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(context);
                          onOpen(entry);
                        },
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

/// 캘린더 + 목록 통합 뷰.
/// - 첫 아이템 = 월 캘린더(스크롤에 포함) + 선택 날짜 요약, 이하 = 대회 카드.
/// - selectedDate == null → 현재 월 목록(날짜순), 아니면 그 날짜 대회만 필터.
/// ListView.builder로 카드를 lazy 렌더한다.
class _TournamentCalendarListView extends StatelessWidget {
  final List<Tournament> tournaments;
  final Set<String> favoriteIds;
  final Set<String> myGradeIds;
  final DateTime focusedMonth;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onClearDate;
  final ValueChanged<DateTime> onSelectNextTournamentDate;
  final ValueChanged<Tournament> onTap;
  final void Function(Tournament tournament, bool isFavorite) onFavoriteToggle;

  const _TournamentCalendarListView({
    required this.tournaments,
    required this.favoriteIds,
    this.myGradeIds = const {},
    required this.focusedMonth,
    required this.selectedDate,
    required this.onMonthChanged,
    required this.onDateSelected,
    required this.onClearDate,
    required this.onSelectNextTournamentDate,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final selected = selectedDate;
    final monthTournaments = _tournamentsInMonth(tournaments, focusedMonth);
    final visible = selected == null
        ? monthTournaments
        : _tournamentsOnDate(tournaments, selected);
    final nextDate =
        selected == null ? null : _nextTournamentDate(tournaments, selected);

    Widget card(Tournament tournament, int seq) {
      final isFavorite = favoriteIds.contains(tournament.id);
      return TournamentCard(
        tournament: tournament,
        isFavorite: isFavorite,
        isMyGrade: myGradeIds.contains(tournament.id),
        seq: seq,
        onTap: () => onTap(tournament),
        onFavoriteToggle: () => onFavoriteToggle(tournament, isFavorite),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      itemCount: 1 + visible.length,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Column(
            children: [
              _TournamentMonthCalendar(
                focusedMonth: focusedMonth,
                selectedDate: selectedDate,
                tournaments: tournaments,
                onMonthChanged: onMonthChanged,
                onDateSelected: onDateSelected,
              ),
              const SizedBox(height: AppSpacing.md),
              _ListHeader(
                focusedMonth: focusedMonth,
                selectedDate: selectedDate,
                monthCount: monthTournaments.length,
                filteredCount: visible.length,
                onClearDate: onClearDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              // 선택 날짜에 대회가 없을 때만 안내 카드(전체 모드는 상위에서 처리).
              if (selected != null && visible.isEmpty)
                _EmptySelectedDateCard(
                  nextDate: nextDate,
                  onSelectNext: nextDate == null
                      ? null
                      : () => onSelectNextTournamentDate(nextDate),
                ),
            ],
          );
        }
        return card(visible[i - 1], i);
      },
    );
  }
}

/// 목록 상단 헤더. 월 모드면 "M월 대회 N개", 날짜 필터 중이면
/// "M월 D일 (요일) · 대회 N개 · [M월 전체]" 로 필터 해제 버튼을 노출.
class _ListHeader extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime? selectedDate;
  final int monthCount;
  final int filteredCount;
  final VoidCallback onClearDate;

  const _ListHeader({
    required this.focusedMonth,
    required this.selectedDate,
    required this.monthCount,
    required this.filteredCount,
    required this.onClearDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = selectedDate;
    final title = date == null
        ? '${focusedMonth.month}월 대회 $monthCount개'
        : '${date.month}월 ${date.day}일 (${_weekdayLabel(date)}) · 대회 $filteredCount개';

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        if (date != null)
          TextButton.icon(
            onPressed: onClearDate,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text('${focusedMonth.month}월 전체'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: cs.primary,
            ),
          ),
      ],
    );
  }
}

class _TournamentMonthCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime? selectedDate;
  final List<Tournament> tournaments;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateSelected;

  const _TournamentMonthCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.tournaments,
    required this.onMonthChanged,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month);
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;
    final leadingEmptyCells = firstDay.weekday % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = _dateOnly(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        // 다크모드에서도 카드 표면이 유지되도록 surface 토큰 사용 (Colors.white 금지).
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.hero,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CalendarMonthButton(
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${focusedMonth.year}년 ${focusedMonth.month}월',
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _CalendarMonthButton(
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final day in const ['일', '월', '화', '수', '목', '금', '토'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: tt.labelSmall?.copyWith(
                        color: day == '일'
                            ? cs.error
                            : day == '토'
                                ? cs.primary
                                : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var row = 0; row < rowCount; row++)
            Builder(
              builder: (context) {
                final weekDates = [
                  for (var col = 0; col < 7; col++)
                    _dateForCell(
                      focusedMonth,
                      leadingEmptyCells,
                      row * 7 + col,
                    ),
                ];
                final bands = bandFlagsForWeek(weekDates, tournaments);
                return Row(
                  children: List.generate(7, (col) {
                    final cellDate = weekDates[col];
                    final band = bands[col];
                    return Expanded(
                      child: _CalendarDayCell(
                        date: cellDate,
                        today: today,
                        selectedDate: selectedDate,
                        count: _tournamentCountOnDate(cellDate, tournaments),
                        hasBand: band.hasBand,
                        isBandStart: band.isBandStart,
                        isBandEnd: band.isBandEnd,
                        onTap: onDateSelected,
                      ),
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }

  DateTime? _dateForCell(DateTime month, int leadingEmptyCells, int index) {
    final day = index - leadingEmptyCells + 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return null;
    return DateTime(month.year, month.month, day);
  }
}

class _CalendarMonthButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;

  const _CalendarMonthButton({required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 36,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        iconSize: 24,
        color: cs.onSurface,
        style: IconButton.styleFrom(
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime? date;
  final DateTime today;
  final DateTime? selectedDate;
  // 그 날짜에 걸친 대회 수. 0이면 표시하지 않는다.
  final int count;
  // 멀티데이 대회 범위 밴드: 그날 걸침 여부 + Row 단위 구간 시작/끝(둥근 모서리).
  final bool hasBand;
  final bool isBandStart;
  final bool isBandEnd;
  final ValueChanged<DateTime> onTap;

  const _CalendarDayCell({
    required this.date,
    required this.today,
    required this.selectedDate,
    required this.count,
    required this.hasBand,
    required this.isBandStart,
    required this.isBandEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final currentDate = date;
    if (currentDate == null) {
      return const SizedBox(height: 46);
    }

    final isSelected =
        selectedDate != null && _isSameDay(currentDate, selectedDate!);
    final isToday = _isSameDay(currentDate, today);

    return InkWell(
      onTap: () => onTap(currentDate),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 멀티데이 대회 범위 밴드: 셀 폭을 꽉 채워 인접 셀과 이어붙고,
            // 날짜 원 뒤(맨 아래) 레이어에 그린다.
            if (hasBand)
              Container(
                height: 30,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.horizontal(
                    left: isBandStart ? const Radius.circular(15) : Radius.zero,
                    right: isBandEnd ? const Radius.circular(15) : Radius.zero,
                  ),
                ),
              ),
            Center(
              child: SizedBox.square(
                dimension: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isSelected ? 34 : 30,
                      height: isSelected ? 34 : 30,
                      decoration: BoxDecoration(
                        color: isSelected ? cs.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: isToday && !isSelected
                            ? Border.all(color: cs.primary, width: 1.3)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${currentDate.day}',
                        style: tt.labelLarge?.copyWith(
                          color: isSelected ? cs.onPrimary : cs.onSurface,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? cs.onPrimary : cs.primary,
                            shape: BoxShape.circle,
                            // 캘린더 카드 배경(surfaceContainerLow)과 동일한 테두리로 배지 분리.
                            border: Border.all(
                              color: cs.surfaceContainerLow,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: tt.labelSmall?.copyWith(
                              color: isSelected ? cs.primary : cs.onPrimary,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySelectedDateCard extends StatelessWidget {
  final DateTime? nextDate;
  final VoidCallback? onSelectNext;

  const _EmptySelectedDateCard({
    required this.nextDate,
    required this.onSelectNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.hero,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_busy_rounded,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이 날짜에는 대회가 없어요',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '가까운 날짜의 대회를 확인해보세요.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (nextDate != null && onSelectNext != null)
            TextButton(
              onPressed: onSelectNext,
              child: Text('${nextDate!.month}/${nextDate!.day} 보기'),
            ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isDateInTournament(DateTime date, Tournament tournament) {
  final target = _dateOnly(date);
  final start = _dateOnly(tournament.startDate);
  final end = _dateOnly(tournament.endDate ?? tournament.startDate);
  return !target.isBefore(start) && !target.isAfter(end);
}

bool _isTournamentInMonth(Tournament tournament, DateTime month) {
  final monthStart = DateTime(month.year, month.month);
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  final start = _dateOnly(tournament.startDate);
  final end = _dateOnly(tournament.endDate ?? tournament.startDate);
  return !end.isBefore(monthStart) && !start.isAfter(monthEnd);
}

List<Tournament> _tournamentsInMonth(
  List<Tournament> tournaments,
  DateTime month,
) {
  return tournaments
      .where((tournament) => _isTournamentInMonth(tournament, month))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

int _tournamentCountOnDate(DateTime? date, List<Tournament> tournaments) {
  if (date == null) return 0;
  return tournaments
      .where((tournament) => _isDateInTournament(date, tournament))
      .length;
}

/// 그 날짜에 2일 이상짜리(멀티데이) 대회가 걸쳐 있으면 true.
/// null 셀(월 앞뒤 여백)은 false로 흡수해 호출부 인접 비교를 단순화한다.
@visibleForTesting
bool multiDayBandOnDate(DateTime? date, List<Tournament> tournaments) {
  if (date == null) return false;
  return tournaments.any(
    (t) =>
        t.endDate != null &&
        _dateOnly(t.endDate!).isAfter(_dateOnly(t.startDate)) &&
        _isDateInTournament(date, t),
  );
}

/// 셀별 밴드 표시/모서리 플래그. Row(주) 단위 인접 비교라 주간 경계는 자동 처리된다.
typedef BandFlags = ({bool hasBand, bool isBandStart, bool isBandEnd});

/// 한 주(7칸, null = 빈 셀) 날짜 배열에 대해 셀별 밴드 플래그를 계산한다.
@visibleForTesting
List<BandFlags> bandFlagsForWeek(
  List<DateTime?> weekDates,
  List<Tournament> tournaments,
) {
  final hasBand =
      weekDates.map((d) => multiDayBandOnDate(d, tournaments)).toList();
  return [
    for (var i = 0; i < weekDates.length; i++)
      (
        hasBand: hasBand[i],
        isBandStart: hasBand[i] && (i == 0 || !hasBand[i - 1]),
        isBandEnd: hasBand[i] && (i == weekDates.length - 1 || !hasBand[i + 1]),
      ),
  ];
}

List<Tournament> _tournamentsOnDate(
  List<Tournament> tournaments,
  DateTime date,
) {
  return tournaments
      .where((tournament) => _isDateInTournament(date, tournament))
      .toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
}

DateTime? _nextTournamentDate(
  List<Tournament> tournaments,
  DateTime selectedDate,
) {
  final selected = _dateOnly(selectedDate);
  final candidates = <DateTime>[];
  for (final tournament in tournaments) {
    final start = _dateOnly(tournament.startDate);
    final end = _dateOnly(tournament.endDate ?? tournament.startDate);
    if (end.isBefore(selected)) continue;
    candidates.add(start.isBefore(selected) ? selected : start);
  }
  if (candidates.isEmpty) return null;
  candidates.sort();
  return candidates.first;
}

String _weekdayLabel(DateTime date) {
  return const ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1];
}

List<Tournament> _previewTournaments(String? sport) {
  final now = DateTime.now();
  if (sport == 'futsal') {
    return [
      Tournament(
        id: 'preview-futsal-sleague-2026',
        sport: 'futsal',
        title: '2026 생활체육 서울시민리그 풋살리그',
        organizer: '서울특별시풋살연맹',
        description:
            '서울시민리그 공식 풋살 페이지 기준 2차 접수는 2026년 5월 1일부터 6월 7일까지, 리그는 2026년 6월 20일부터 10월 11일까지 진행됩니다.',
        startDate: DateTime(2026, 6, 20),
        endDate: DateTime(2026, 10, 11),
        applicationDeadline: DateTime(2026, 6, 7),
        region: '서울',
        location: '서울시민리그 풋살 공식 경기장소',
        eligibleGrades: const [
          'intro',
          'beginner',
          'intermediate',
          'advanced',
          'elite',
        ],
        prize: null,
        format: '서울시민리그 풋살 리그전',
        sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
        status: 'published',
        futsalEventCategory: 'sports_for_all',
      ),
      Tournament(
        id: 'preview-futsal-1',
        sport: 'futsal',
        title: '서울 풋살 위클리 컵',
        organizer: '올라운드 풋살 커뮤니티',
        description: '주말 저녁에 열리는 5대5 풋살 모집전',
        startDate: now.add(const Duration(days: 9)),
        endDate: now.add(const Duration(days: 9)),
        applicationDeadline: now.add(const Duration(days: 4)),
        region: '수도권',
        location: '서울 송파 풋살파크',
        eligibleGrades: const ['intro', 'beginner', 'intermediate'],
        entryFee: 80000,
        prize: '우승팀 구장 이용권',
        format: '5대5 조별리그',
        status: 'published',
        futsalEventCategory: 'private',
      ),
      Tournament(
        id: 'preview-futsal-2',
        sport: 'futsal',
        title: '부산 야간 풋살 리그',
        organizer: '부산 풋살 연합',
        description: '퇴근 후 참여 가능한 지역 풋살 리그',
        startDate: now.add(const Duration(days: 18)),
        endDate: now.add(const Duration(days: 18)),
        applicationDeadline: now.add(const Duration(days: 11)),
        region: '부산·울산·경남',
        location: '부산 사직 풋살장',
        eligibleGrades: const ['advanced', 'elite'],
        entryFee: 100000,
        prize: '우승 트로피',
        format: '토너먼트',
        status: 'published',
        futsalEventCategory: 'regional_federation',
      ),
    ];
  }
  return [
    Tournament(
      id: 'preview-tennis-1',
      sport: 'tennis',
      title: '광주 오픈 테니스 챌린지',
      organizer: '광주테니스협회',
      description: '지역 동호인을 위한 복식 대회',
      startDate: now.add(const Duration(days: 12)),
      endDate: now.add(const Duration(days: 13)),
      applicationDeadline: now.add(const Duration(days: 5)),
      region: '광주',
      location: '염주실내테니스장',
      eligibleGrades: const ['under1y', 'y1to3'],
      entryFee: 40000,
      entryFeeUnit: 'per_person',
      prize: '우승 상품권',
      format: '복식 조별리그',
      status: 'published',
    ),
    Tournament(
      id: 'preview-tennis-2',
      sport: 'tennis',
      title: '수도권 동호인 랭킹전',
      organizer: 'KATA 수도권 지부',
      description: '등급별 자동 추천에 맞춘 랭킹전',
      startDate: now.add(const Duration(days: 21)),
      endDate: now.add(const Duration(days: 21)),
      applicationDeadline: now.add(const Duration(days: 14)),
      region: '수도권',
      location: '분당 테니스파크',
      eligibleGrades: const ['y3to5', 'over5y'],
      entryFee: 50000,
      entryFeeUnit: 'per_person',
      prize: '랭킹 포인트',
      format: '복식 토너먼트',
      status: 'published',
    ),
  ];
}

class _PreviewDataBanner extends StatelessWidget {
  const _PreviewDataBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: cs.tertiaryContainer.withValues(alpha: 0.7),
      child: Row(
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 18,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '백엔드 연결 전 디자인 미리보기 데이터입니다.',
              style: tt.labelMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentErrorState extends StatelessWidget {
  const _TournamentErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              '대회 목록을 불러올 수 없어요',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 상세검색 바텀시트 ─────────────────────────────────────────────────────────

class _SearchFilterResult {
  final String query;
  final bool onlyMyGrade;
  final String? regionCode;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? hostOrg;

  /// 부서 선택의 source of truth = 라벨(테니스: 부서 라벨, 풋살: grade 코드).
  final Set<String> divisionLabels;
  final RecruitingStatus recruiting;

  const _SearchFilterResult({
    required this.query,
    required this.onlyMyGrade,
    this.regionCode,
    this.dateFrom,
    this.dateTo,
    this.hostOrg,
    this.divisionLabels = const {},
    this.recruiting = RecruitingStatus.all,
  });
}

class _SearchFilterSheet extends StatefulWidget {
  final String? sport;
  final _SearchFilterResult initial;

  const _SearchFilterSheet({required this.sport, required this.initial});

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late final TextEditingController _queryCtrl;
  late bool _onlyMyGrade;
  String? _regionCode;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _hostOrg;
  late Set<String> _selectedDivisionLabels;
  late Set<String> _selectedFutsalGrades;
  late RecruitingStatus _recruitingStatus;
  late DatePreset _datePreset;

  bool get _isTennis => widget.sport == 'tennis';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _queryCtrl = TextEditingController(text: initial.query);
    _onlyMyGrade = initial.onlyMyGrade;
    _regionCode = initial.regionCode;
    _dateFrom = initial.dateFrom;
    _dateTo = initial.dateTo;
    _hostOrg = initial.hostOrg;
    _recruitingStatus = initial.recruiting;
    // 기존 범위 → 프리셋 역추론(표준 프리셋이면 강조, 아니면 custom).
    _datePreset = presetForRange(
      initial.dateFrom,
      initial.dateTo,
      DateTime.now(),
    );

    // 부서 선택은 이미 라벨 source of truth → 그대로 받는다.
    // 테니스: 현재 협회 스코프에 존재하는 라벨만 유지(스코프 밖 라벨 제거).
    if (_isTennis) {
      final allowed = _divisionLabelsForScope(_hostOrg).toSet();
      _selectedDivisionLabels =
          initial.divisionLabels.where(allowed.contains).toSet();
      _selectedFutsalGrades = const {};
    } else {
      _selectedFutsalGrades = {
        for (final g in futsalGrades)
          if (initial.divisionLabels.contains(g)) g,
      };
      _selectedDivisionLabels = const {};
    }
  }

  /// 현재 협회 스코프의 부서 라벨 목록.
  /// org == null → 전 협회 union, org != null → 그 협회만.
  List<String> _divisionLabelsForScope(String? org) =>
      org == null ? tennisDivisionLabels() : tennisDivisionLabelsForOrg(org);

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 현재 부서/등급 선택 라벨 집합(source of truth).
  /// 테니스: 부서 라벨, 풋살: grade 코드.
  Set<String> _selectedDivisionResult() =>
      _isTennis ? _selectedDivisionLabels : _selectedFutsalGrades;

  /// 협회(_hostOrg) 변경 시: 새 스코프에 없는 선택 라벨은 자동 해제.
  void _setHostOrg(String? org) {
    setState(() {
      _hostOrg = org;
      final allowed = _divisionLabelsForScope(org).toSet();
      _selectedDivisionLabels =
          _selectedDivisionLabels.where(allowed.contains).toSet();
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _SearchFilterResult(
        query: _queryCtrl.text.trim(),
        onlyMyGrade: _onlyMyGrade,
        regionCode: _regionCode,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        hostOrg: _isTennis ? _hostOrg : null,
        divisionLabels: _selectedDivisionResult(),
        recruiting: _recruitingStatus,
      ),
    );
  }

  void _reset() {
    setState(() {
      _queryCtrl.clear();
      _onlyMyGrade = false;
      _regionCode = null;
      _dateFrom = null;
      _dateTo = null;
      _datePreset = DatePreset.all;
      _hostOrg = null;
      _selectedDivisionLabels = {};
      _selectedFutsalGrades = {};
      _recruitingStatus = RecruitingStatus.all;
    });
  }

  /// 프리셋 칩 선택 → 범위 환원. custom 은 picker 를 띄운다.
  void _selectDatePreset(DatePreset preset) {
    if (preset == DatePreset.custom) {
      _pickDateRange();
      return;
    }
    final (from, to) = dateRangeForPreset(preset, DateTime.now());
    setState(() {
      _datePreset = preset;
      _dateFrom = from;
      _dateTo = to;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, 1, 1);
    final lastDate = DateTime(now.year + 2, 12, 31);
    final initialRange = (_dateFrom != null && _dateTo != null)
        ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialRange,
      helpText: '기간 선택',
      saveText: '적용',
    );
    if (picked != null) {
      setState(() {
        _dateFrom = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _dateTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
        // 직접 고른 범위가 표준 프리셋과 일치할 수도 있으므로 역추론.
        _datePreset = presetForRange(_dateFrom, _dateTo, now);
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '상세검색',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _queryCtrl,
                        decoration: InputDecoration(
                          hintText: '대회명·주최·설명 검색',
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
                        onSubmitted: (_) => _apply(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildRegionSection(cs, tt),
                      const SizedBox(height: AppSpacing.lg),
                      _buildDateSection(cs, tt),
                      if (_isTennis) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _buildHostOrgSection(cs, tt),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _buildDivisionSection(cs, tt),
                      const SizedBox(height: AppSpacing.lg),
                      _buildRecruitingSection(cs, tt),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile(
                        title: Text(
                          '내 등급만 보기',
                          style: tt.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text('내 등급 이하 대회만 표시'),
                        value: _onlyMyGrade,
                        onChanged: (v) => setState(() => _onlyMyGrade = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('초기화'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('검색'),
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

  Widget _buildSectionLabel(TextTheme tt, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label,
        style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildRegionSection(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(tt, '지역'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _filterChip(
              label: '전체',
              selected: _regionCode == null,
              onSelected: (_) => setState(() => _regionCode = null),
            ),
            for (final code in regionCodes)
              _filterChip(
                label: regionLabel(code),
                selected: _regionCode == code,
                onSelected: (selected) =>
                    setState(() => _regionCode = selected ? code : null),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateSection(ColorScheme cs, TextTheme tt) {
    final hasRange = _dateFrom != null && _dateTo != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(tt, '기간'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final preset in DatePreset.values)
              _filterChip(
                label: datePresetLabel(preset),
                selected: _datePreset == preset,
                onSelected: (_) => _selectDatePreset(preset),
              ),
          ],
        ),
        if (hasRange) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 16, color: cs.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${_formatDate(_dateFrom!)} ~ ${_formatDate(_dateTo!)}',
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _dateFrom = null;
                  _dateTo = null;
                  _datePreset = DatePreset.all;
                }),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: '기간 해제',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRecruitingSection(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(tt, '모집 상태'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final status in RecruitingStatus.values)
              _filterChip(
                label: recruitingStatusLabel(status),
                selected: _recruitingStatus == status,
                onSelected: (_) => setState(() => _recruitingStatus = status),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHostOrgSection(ColorScheme cs, TextTheme tt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(tt, '주최 협회'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _filterChip(
              label: '전체',
              selected: _hostOrg == null,
              onSelected: (_) => _setHostOrg(null),
            ),
            for (final org in tennisOrgs)
              _filterChip(
                label: tennisOrgShortLabel(org),
                selected: _hostOrg == org,
                onSelected: (selected) => _setHostOrg(selected ? org : null),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDivisionSection(ColorScheme cs, TextTheme tt) {
    final List<Widget> chips;
    if (_isTennis) {
      // 협회 선택 시 그 협회 부서만, 미선택 시 전 협회 union 라벨.
      chips = [
        for (final label in _divisionLabelsForScope(_hostOrg))
          _filterChip(
            label: label,
            selected: _selectedDivisionLabels.contains(label),
            onSelected: (selected) => setState(() {
              final next = Set<String>.from(_selectedDivisionLabels);
              if (selected) {
                next.add(label);
              } else {
                next.remove(label);
              }
              _selectedDivisionLabels = next;
            }),
          ),
      ];
    } else {
      chips = [
        for (final grade in futsalGrades)
          _filterChip(
            label: gradeLabel(grade),
            selected: _selectedFutsalGrades.contains(grade),
            onSelected: (selected) => setState(() {
              final next = Set<String>.from(_selectedFutsalGrades);
              if (selected) {
                next.add(grade);
              } else {
                next.remove(grade);
              }
              _selectedFutsalGrades = next;
            }),
          ),
      ];
    }

    final scopeHint = _isTennis && _hostOrg != null
        ? '${tennisOrgShortLabel(_hostOrg!)} 부서'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildSectionLabel(tt, _isTennis ? '부서' : '등급'),
            if (scopeHint != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  scopeHint,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: chips,
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surface,
      side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
      labelStyle: TextStyle(
        color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// 최초 로드용 플레이스홀더. 카드 크기의 회색 박스로 레이아웃 점프를 줄인다.
/// (skeletonizer 패키지는 최신 Flutter Canvas API와 비호환이라 의존하지 않는다.)
class _TournamentSkeletonList extends StatelessWidget {
  const _TournamentSkeletonList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            height: 92,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppRadius.card,
              border: Border.all(color: cs.outlineVariant),
            ),
          ),
      ],
    );
  }
}
