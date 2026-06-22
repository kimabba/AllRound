import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/matchup_logo.dart';
import '../../widgets/tournament_card.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  bool _onlyMyGrade = false;
  String _q = '';
  List<Tournament>? _results;
  bool _loading = false;
  bool _usingPreviewData = false;
  String? _error;
  _TournamentViewMode _viewMode = _TournamentViewMode.list;
  late DateTime _selectedDate;
  late DateTime _focusedMonth;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _search() async {
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
      res = await api.searchTournaments(
        sport: ref.read(activeSportProvider),
        onlyMyGrade: _onlyMyGrade,
        query: _q,
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
    _selectedDate = _today;
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _search());
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '대회 · 모집'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '대회 제보',
            onPressed: () => context.push('/tournaments/submit'),
          ),
        ],
      ),
      body: Column(
        children: [
          const _MyGradeSection(),
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
                _ViewModeSegment(
                  selected: _viewMode,
                  onChanged: (mode) => setState(() => _viewMode = mode),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_viewMode == _TournamentViewMode.list)
                  _buildQuickFilters(cs)
                else
                  _buildCalendarFilterControls(cs),
              ],
            ),
          ),
          if (_loading) LinearProgressIndicator(color: cs.primary),
          if (_usingPreviewData) const _PreviewDataBanner(),
          Expanded(
            child: _error != null
                ? _TournamentErrorState(message: _error!, onRetry: _search)
                : _results == null
                    ? const SizedBox.shrink()
                    : _results!.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.search_off_rounded,
                            title: '검색 결과 없음',
                            description: '다른 검색어나 필터로 시도해 보세요.',
                          )
                        : _viewMode == _TournamentViewMode.list
                            ? _TournamentListView(
                                tournaments: _results!,
                                favoriteIds:
                                    favorites.valueOrNull ?? const <String>{},
                                onTap: (tournament) => context
                                    .push('/tournaments/${tournament.id}'),
                                onFavoriteToggle:
                                    (tournament, isFavorite) async {
                                  await ref.read(apiProvider).toggleFavorite(
                                        tournament.id,
                                        !isFavorite,
                                      );
                                  ref.invalidate(favoriteIdsProvider);
                                },
                              )
                            : _TournamentCalendarView(
                                tournaments: _results!,
                                favoriteIds:
                                    favorites.valueOrNull ?? const <String>{},
                                focusedMonth: _focusedMonth,
                                selectedDate: _selectedDate,
                                onMonthChanged: (month) {
                                  setState(() {
                                    _focusedMonth = month;
                                    if (_selectedDate.year != month.year ||
                                        _selectedDate.month != month.month) {
                                      _selectedDate =
                                          DateTime(month.year, month.month);
                                    }
                                  });
                                },
                                onDateSelected: (date) {
                                  setState(() => _selectedDate = date);
                                },
                                onSelectNextTournamentDate: (date) {
                                  setState(() {
                                    _selectedDate = date;
                                    _focusedMonth =
                                        DateTime(date.year, date.month);
                                  });
                                },
                                onTap: (tournament) => context
                                    .push('/tournaments/${tournament.id}'),
                                onFavoriteToggle:
                                    (tournament, isFavorite) async {
                                  await ref.read(apiProvider).toggleFavorite(
                                        tournament.id,
                                        !isFavorite,
                                      );
                                  ref.invalidate(favoriteIdsProvider);
                                },
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFilters(ColorScheme cs) {
    final hasActiveFilters = _onlyMyGrade || _q.trim().isNotEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FilterPill(
              label: '전체',
              selected: !hasActiveFilters,
              onTap: () {
                if (hasActiveFilters) {
                  setState(() {
                    _onlyMyGrade = false;
                    _q = '';
                  });
                  _search();
                }
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            _FilterPill(
              label: '이번주',
              selected: false,
              onTap: _search,
            ),
          ],
        ),
        ActionChip(
          avatar: Icon(
            Icons.tune_rounded,
            size: 18,
            color: hasActiveFilters ? cs.primary : cs.onSurfaceVariant,
          ),
          label: Text(hasActiveFilters ? '필터 적용됨' : '상세검색'),
          onPressed: () => _openSearchSheet(cs),
          backgroundColor:
              hasActiveFilters ? cs.primaryContainer : cs.surfaceContainerHigh,
        ),
      ],
    );
  }

  Future<void> _openSearchSheet(ColorScheme cs) async {
    final result = await showModalBottomSheet<_SearchFilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchFilterSheet(
        initialQuery: _q,
        initialOnlyMyGrade: _onlyMyGrade,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _q = result.query;
        _onlyMyGrade = result.onlyMyGrade;
      });
      _search();
    }
  }

  Widget _buildCalendarFilterControls(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final activeFilters = <String>[
      if (_onlyMyGrade) '내 등급',
      if (_q.trim().isNotEmpty) '검색어',
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
            borderRadius: BorderRadius.circular(16),
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

enum _TournamentViewMode { list, calendar }

class _ViewModeSegment extends StatelessWidget {
  final _TournamentViewMode selected;
  final ValueChanged<_TournamentViewMode> onChanged;

  const _ViewModeSegment({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _ViewModeButton(
            label: '목록',
            icon: Icons.format_list_bulleted_rounded,
            selected: selected == _TournamentViewMode.list,
            textTheme: tt,
            colorScheme: cs,
            onTap: () => onChanged(_TournamentViewMode.list),
          ),
          _ViewModeButton(
            label: '일정',
            icon: Icons.calendar_month_rounded,
            selected: selected == _TournamentViewMode.calendar,
            textTheme: tt,
            colorScheme: cs,
            onTap: () => onChanged(_TournamentViewMode.calendar),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.textTheme,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentListView extends StatelessWidget {
  final List<Tournament> tournaments;
  final Set<String> favoriteIds;
  final ValueChanged<Tournament> onTap;
  final void Function(Tournament tournament, bool isFavorite) onFavoriteToggle;

  const _TournamentListView({
    required this.tournaments,
    required this.favoriteIds,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      itemCount: tournaments.length,
      itemBuilder: (_, i) {
        final tournament = tournaments[i];
        final isFavorite = favoriteIds.contains(tournament.id);
        return TournamentCard(
          tournament: tournament,
          isFavorite: isFavorite,
          onTap: () => onTap(tournament),
          onFavoriteToggle: () => onFavoriteToggle(tournament, isFavorite),
        );
      },
    );
  }
}

class _TournamentCalendarView extends StatelessWidget {
  final List<Tournament> tournaments;
  final Set<String> favoriteIds;
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onSelectNextTournamentDate;
  final ValueChanged<Tournament> onTap;
  final void Function(Tournament tournament, bool isFavorite) onFavoriteToggle;

  const _TournamentCalendarView({
    required this.tournaments,
    required this.favoriteIds,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onMonthChanged,
    required this.onDateSelected,
    required this.onSelectNextTournamentDate,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTournaments = _tournamentsOnDate(tournaments, selectedDate);
    final nextDate = _nextTournamentDate(tournaments, selectedDate);

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      children: [
        _TournamentMonthCalendar(
          focusedMonth: focusedMonth,
          selectedDate: selectedDate,
          tournaments: tournaments,
          onMonthChanged: onMonthChanged,
          onDateSelected: onDateSelected,
        ),
        const SizedBox(height: AppSpacing.md),
        _SelectedDateTournamentPanel(
          selectedDate: selectedDate,
          count: selectedTournaments.length,
          child: selectedTournaments.isEmpty
              ? _EmptySelectedDateCard(
                  nextDate: nextDate,
                  onSelectNext: nextDate == null
                      ? null
                      : () => onSelectNextTournamentDate(nextDate),
                )
              : Column(
                  children: [
                    for (final tournament in selectedTournaments)
                      TournamentCard(
                        tournament: tournament,
                        isFavorite: favoriteIds.contains(tournament.id),
                        onTap: () => onTap(tournament),
                        onFavoriteToggle: () => onFavoriteToggle(
                          tournament,
                          favoriteIds.contains(tournament.id),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TournamentMonthCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
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
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final leadingEmptyCells = firstDay.weekday % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = _dateOnly(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _CalendarDayCell(
                      date: _dateForCell(
                        focusedMonth,
                        leadingEmptyCells,
                        row * 7 + col,
                      ),
                      today: today,
                      selectedDate: selectedDate,
                      count: _dateForCell(
                                focusedMonth,
                                leadingEmptyCells,
                                row * 7 + col,
                              ) ==
                              null
                          ? 0
                          : _tournamentsOnDate(
                              tournaments,
                              _dateForCell(
                                focusedMonth,
                                leadingEmptyCells,
                                row * 7 + col,
                              )!,
                            ).length,
                      onTap: onDateSelected,
                    ),
                  ),
              ],
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

  const _CalendarMonthButton({
    required this.onPressed,
    required this.icon,
  });

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
  final DateTime selectedDate;
  final int count;
  final ValueChanged<DateTime> onTap;

  const _CalendarDayCell({
    required this.date,
    required this.today,
    required this.selectedDate,
    required this.count,
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

    final isSelected = _isSameDay(currentDate, selectedDate);
    final isToday = _isSameDay(currentDate, today);

    return InkWell(
      onTap: () => onTap(currentDate),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 46,
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isSelected ? 36 : 32,
                  height: isSelected ? 36 : 32,
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
                    right: count > 1 ? 0 : 6,
                    bottom: count > 1 ? 0 : 4,
                    child: count == 1
                        ? Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected ? cs.onPrimary : cs.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : Container(
                            height: 16,
                            constraints: const BoxConstraints(minWidth: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? cs.onPrimary : cs.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: tt.labelSmall?.copyWith(
                                color: isSelected ? cs.primary : cs.onPrimary,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
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

class _SelectedDateTournamentPanel extends StatelessWidget {
  final DateTime selectedDate;
  final int count;
  final Widget child;

  const _SelectedDateTournamentPanel({
    required this.selectedDate,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SelectedDateHeader(
            selectedDate: selectedDate,
            count: count,
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _SelectedDateHeader extends StatelessWidget {
  final DateTime selectedDate;
  final int count;

  const _SelectedDateHeader({
    required this.selectedDate,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${selectedDate.month}월 ${selectedDate.day}일 (${_weekdayLabel(selectedDate)})',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: count > 0
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '대회 $count개',
            style: tt.labelMedium?.copyWith(
              color: count > 0 ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(20),
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
          'elite'
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
          Icon(Icons.visibility_rounded,
              size: 18, color: cs.onTertiaryContainer),
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

class _FilterPill extends StatelessWidget {
  const _FilterPill({
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

    return Material(
      color: selected ? cs.primary : cs.surface,
      borderRadius: AppRadius.pill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: tt.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyGradeSection extends ConsumerWidget {
  const _MyGradeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  '내 등급 추천 대회',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          tournaments.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final favs = favorites.valueOrNull ?? const <String>{};
              return SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final tournament = list[i];
                    return SizedBox(
                      width: 260,
                      child: TournamentCard(
                        tournament: tournament,
                        compact: true,
                        isFavorite: favs.contains(tournament.id),
                        onTap: () =>
                            context.push('/tournaments/${tournament.id}'),
                        onFavoriteToggle: () async {
                          final api = ref.read(apiProvider);
                          await api.toggleFavorite(
                            tournament.id,
                            !favs.contains(tournament.id),
                          );
                          ref.invalidate(favoriteIdsProvider);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Divider(color: cs.outlineVariant, height: 1),
        ],
      ),
    );
  }
}

// ─── 상세검색 바텀시트 ─────────────────────────────────────────────────────────

class _SearchFilterResult {
  final String query;
  final bool onlyMyGrade;
  const _SearchFilterResult({required this.query, required this.onlyMyGrade});
}

class _SearchFilterSheet extends StatefulWidget {
  final String initialQuery;
  final bool initialOnlyMyGrade;

  const _SearchFilterSheet({
    required this.initialQuery,
    required this.initialOnlyMyGrade,
  });

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late final TextEditingController _queryCtrl;
  late bool _onlyMyGrade;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _onlyMyGrade = widget.initialOnlyMyGrade;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.of(context).pop(
      _SearchFilterResult(
        query: _queryCtrl.text.trim(),
        onlyMyGrade: _onlyMyGrade,
      ),
    );
  }

  void _reset() {
    setState(() {
      _queryCtrl.clear();
      _onlyMyGrade = false;
    });
  }

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '상세검색',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _queryCtrl,
              autofocus: true,
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
            SwitchListTile(
              title: Text(
                '내 등급만 보기',
                style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('내 등급 이하 대회만 표시'),
              value: _onlyMyGrade,
              onChanged: (v) => setState(() => _onlyMyGrade = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.lg),
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
    );
  }
}
