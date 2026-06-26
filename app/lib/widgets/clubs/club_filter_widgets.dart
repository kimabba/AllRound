import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';

class ClubSearchFilters {
  final String? region;
  final String? gender;
  final Set<String> days;
  final RangeValues feeRange;

  const ClubSearchFilters({
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
        if (gender != null) clubGenderLabel(gender),
        for (final day in days) day,
        if (feeRange.start > 0 || feeRange.end < 100000)
          '${formatFee(feeRange.start)}~${formatFee(feeRange.end)}',
      ];

  ClubSearchFilters copyWith({
    String? region,
    bool clearRegion = false,
    String? gender,
    bool clearGender = false,
    Set<String>? days,
    RangeValues? feeRange,
  }) {
    return ClubSearchFilters(
      region: clearRegion ? null : (region ?? this.region),
      gender: clearGender ? null : (gender ?? this.gender),
      days: days ?? this.days,
      feeRange: feeRange ?? this.feeRange,
    );
  }

  ClubSearchFilters cleared() => const ClubSearchFilters();
}

class ClubFilterResult {
  final ClubSearchFilters filters;
  final Set<String> interests;

  const ClubFilterResult({
    required this.filters,
    required this.interests,
  });
}

String formatFee(double value) {
  final amount = value.round();
  if (amount == 0) return '0원';
  if (amount >= 100000) return '10만원+';
  if (amount % 10000 == 0) return '${amount ~/ 10000}만원';
  return '${amount ~/ 1000}천원';
}

class InterestSheet extends StatefulWidget {
  final Set<String> initialInterests;

  const InterestSheet({super.key, required this.initialInterests});

  @override
  State<InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends State<InterestSheet> {
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
                SportInterestChip(
                  sport: 'tennis',
                  selected: _selected.contains('tennis'),
                  onTap: _toggleSport,
                ),
                SportInterestChip(
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

class SportInterestChip extends StatelessWidget {
  final String sport;
  final bool selected;
  final ValueChanged<String> onTap;

  const SportInterestChip({
    super.key,
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

class ClubFilterSheet extends StatefulWidget {
  final ClubSearchFilters initialFilters;
  final Set<String> initialInterests;
  final String title;
  final IconData icon;
  final Color accentColor;
  final Color onAccentColor;

  const ClubFilterSheet({
    super.key,
    required this.initialFilters,
    required this.initialInterests,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onAccentColor,
  });

  @override
  State<ClubFilterSheet> createState() => _ClubFilterSheetState();
}

class _ClubFilterSheetState extends State<ClubFilterSheet> {
  static const _regions = ['서울', '경기', '인천', '광주', '부산', '대구', '대전'];
  static const _genders = ['여성', '남성', '혼성'];
  static const _days = ['월', '화', '수', '목', '금', '토', '일'];

  late ClubSearchFilters _filters = widget.initialFilters;
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
            FilterSection(
              title: '종목',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SportInterestChip(
                      sport: 'tennis',
                      selected: _selectedInterests.contains('tennis'),
                      onTap: _selectSport,
                    ),
                    SportInterestChip(
                      sport: 'futsal',
                      selected: _selectedInterests.contains('futsal'),
                      onTap: _selectSport,
                    ),
                  ],
                ),
              ],
            ),
            FilterSection(
              title: '지역',
              children: [
                FilterChipWrap(
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
            FilterSection(
              title: '성별',
              children: [
                FilterChipWrap(
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
            FilterSection(
              title: '모임요일',
              children: [
                FilterChipWrap(
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
            FilterSection(
              title:
                  '월회비 ${formatFee(_filters.feeRange.start)} ~ ${formatFee(_filters.feeRange.end)}',
              children: [
                RangeSlider(
                  values: _filters.feeRange,
                  min: 0,
                  max: 100000,
                  divisions: 20,
                  labels: RangeLabels(
                    formatFee(_filters.feeRange.start),
                    formatFee(_filters.feeRange.end),
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
                          ? const {'tennis', 'futsal'}
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
                      ClubFilterResult(
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

class FilterSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FilterSection({
    super.key,
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

class FilterChipWrap extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onSelected;

  const FilterChipWrap({
    super.key,
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
