import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

class FriendScheduleScreen extends StatefulWidget {
  const FriendScheduleScreen({super.key});

  @override
  State<FriendScheduleScreen> createState() => _FriendScheduleScreenState();
}

class _FriendScheduleScreenState extends State<FriendScheduleScreen> {
  late DateTime _today;
  late DateTime _month;
  _FriendListMode _mode = _FriendListMode.activity;
  int? _selectedDay;

  static const Map<String, List<_FriendActivityType>> _activityByDate = {
    '2026-05-24': [_FriendActivityType.club],
    '2026-05-30': [_FriendActivityType.tournament],
    '2026-06-09': [_FriendActivityType.tournament],
    '2026-06-11': [_FriendActivityType.club],
    '2026-06-14': [_FriendActivityType.tournament, _FriendActivityType.club],
    '2026-06-18': [_FriendActivityType.club],
    '2026-06-21': [_FriendActivityType.tournament],
    '2026-06-26': [_FriendActivityType.club],
    '2026-07-03': [_FriendActivityType.club],
    '2026-07-12': [_FriendActivityType.tournament],
    '2026-07-19': [_FriendActivityType.tournament, _FriendActivityType.club],
  };

  static const Map<String, List<_FriendActivityPreview>> _activityDetailByDate =
      {
    '2026-05-24': [
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '준호',
        title: '서울 풋살 러너스 정기 모임',
        status: '참석 예정',
      ),
    ],
    '2026-05-30': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '서연',
        title: '광주 오픈 테니스 챌린지',
        status: '참가 확정',
      ),
    ],
    '2026-06-09': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '지훈',
        title: '광주 오픈 테니스 챌린지',
        status: '참가 확정',
      ),
    ],
    '2026-06-11': [
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '준호',
        title: '서울 풋살 러너스 번개 모임',
        status: '참석 예정',
      ),
    ],
    '2026-06-14': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '지훈',
        title: '광주 오픈 테니스 챌린지',
        status: '참가 확정',
      ),
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '서연',
        title: '광주 테니스 크루 정기 모임',
        status: '참석 예정',
      ),
    ],
    '2026-06-18': [
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '준호',
        title: '서울 풋살 러너스 훈련',
        status: '참석 예정',
      ),
    ],
    '2026-06-21': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '민지',
        title: '2026 생활체육 서울시민리그 풋살리그',
        status: '대회 신청 완료',
      ),
    ],
    '2026-06-26': [
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '준호',
        title: '서울 풋살 러너스 정기 모임',
        status: '참석 예정',
      ),
    ],
    '2026-07-03': [
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '민지',
        title: '수도권 풋살 위클리',
        status: '참석 예정',
      ),
    ],
    '2026-07-12': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '지훈',
        title: '여름 테니스 챔피언십',
        status: '참가 확정',
      ),
    ],
    '2026-07-19': [
      _FriendActivityPreview(
        type: _FriendActivityType.tournament,
        friendName: '민지',
        title: '서울 풋살 썸머컵',
        status: '대회 신청 완료',
      ),
      _FriendActivityPreview(
        type: _FriendActivityType.club,
        friendName: '준호',
        title: '서울 풋살 러너스 친선전',
        status: '참석 예정',
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _month = DateTime(_today.year, _today.month);
    _selectedDay = _today.day;
  }

  Map<int, List<_FriendActivityType>> get _activityByDay {
    final result = <int, List<_FriendActivityType>>{};
    for (final entry in _activityByDate.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == _month.year && date.month == _month.month) {
        result[date.day] = entry.value;
      }
    }
    return result;
  }

  Map<int, List<_FriendActivityPreview>> get _activityDetailByDay {
    final result = <int, List<_FriendActivityPreview>>{};
    for (final entry in _activityDetailByDate.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      if (date.year == _month.year && date.month == _month.month) {
        result[date.day] = entry.value;
      }
    }
    return result;
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = _month.year == _today.year && _month.month == _today.month
          ? _today.day
          : _firstActivityDayForMonth();
      _mode = _FriendListMode.activity;
    });
  }

  int? _firstActivityDayForMonth() {
    final days = _activityDetailByDay.keys.toList()..sort();
    return days.isEmpty ? null : days.first;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '뒤로가기',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/more');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          '친구 일정',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '검색',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded, size: 30),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: '알림',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded, size: 30),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: [
          const SizedBox(height: AppSpacing.xs),
          _MonthHeader(
            month: _month,
            onPrevious: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: _CalendarGrid(
              month: _month,
              today: _today,
              activityByDay: _activityByDay,
              selectedDay: _selectedDay,
              onDaySelected: (day) => setState(() {
                _selectedDay = day;
                _mode = _FriendListMode.activity;
              }),
            ),
          ),
          if (_selectedDay != null &&
              _activityDetailByDay[_selectedDay] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _SelectedDayActivities(
                day: _selectedDay!,
                items: _activityDetailByDay[_selectedDay]!,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _FriendActivitySummary(
              mode: _mode,
              onModeChanged: (mode) => setState(() => _mode = mode),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _FriendList(mode: _mode),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundIconButton(
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            '${month.year}년 ${month.month}월',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _RoundIconButton(
          icon: Icons.chevron_right_rounded,
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        backgroundColor: cs.surfaceContainerLow,
        foregroundColor: cs.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      icon: Icon(icon, size: 28),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Map<int, List<_FriendActivityType>> activityByDay;
  final int? selectedDay;
  final ValueChanged<int> onDaySelected;

  const _CalendarGrid({
    required this.month,
    required this.today,
    required this.activityByDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final leadingDays = first.weekday % 7;
    final firstCell = first.subtract(Duration(days: leadingDays));
    final days = List.generate(35, (i) => firstCell.add(Duration(days: i)));

    return Column(
      children: [
        const _WeekdayRow(),
        const SizedBox(height: AppSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 4,
            childAspectRatio: 0.98,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            return _CalendarDay(
              day: day,
              activeMonth: month.month,
              isToday: _isSameDay(day, today),
              isSelected: day.month == month.month && selectedDay == day.day,
              activities:
                  day.month == month.month ? activityByDay[day.day] : null,
              onTap: day.month == month.month && activityByDay[day.day] != null
                  ? () => onDaySelected(day.day)
                  : null,
            );
          },
        ),
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < _weekdays.length; i++)
          Expanded(
            child: Text(
              _weekdays[i],
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: switch (i) {
                      0 => cs.error,
                      6 => cs.primary,
                      _ => cs.onSurface,
                    },
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  final DateTime day;
  final int activeMonth;
  final bool isToday;
  final bool isSelected;
  final List<_FriendActivityType>? activities;
  final VoidCallback? onTap;

  const _CalendarDay({
    required this.day,
    required this.activeMonth,
    required this.isToday,
    required this.isSelected,
    this.activities,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inMonth = day.month == activeMonth;
    final muted = cs.outline;
    final primary = cs.primary;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            isToday ? '오늘' : '${day.day}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  color: isSelected
                      ? Colors.white
                      : isToday
                          ? primary
                          : inMonth
                              ? cs.onSurface
                              : muted,
                  fontWeight:
                      isToday || isSelected ? FontWeight.w900 : FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 8,
          child: activities != null && activities!.isNotEmpty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final activity in activities!)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: switch (activity) {
                            _FriendActivityType.tournament => cs.primary,
                            _FriendActivityType.club => cs.onSurfaceVariant,
                          },
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                )
              : null,
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: content,
      ),
    );
  }
}

enum _FriendActivityType { tournament, club }

enum _FriendListMode { activity, clubs, tournaments }

class _FriendActivityPreview {
  final _FriendActivityType type;
  final String friendName;
  final String title;
  final String status;

  const _FriendActivityPreview({
    required this.type,
    required this.friendName,
    required this.title,
    required this.status,
  });
}

class _SelectedDayActivities extends StatelessWidget {
  final int day;
  final List<_FriendActivityPreview> items;

  const _SelectedDayActivities({
    required this.day,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '6월 $day일 친구 일정',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 6),
          for (final item in items) _SelectedDayActivityRow(item: item),
        ],
      ),
    );
  }
}

class _SelectedDayActivityRow extends StatelessWidget {
  final _FriendActivityPreview item;

  const _SelectedDayActivityRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTournament = item.type == _FriendActivityType.tournament;
    final color = cs.primary;
    final icon =
        isTournament ? Icons.emoji_events_rounded : Icons.groups_rounded;
    final label = isTournament ? '대회' : '클럽';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${item.friendName}님 · ${item.status}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendActivitySummary extends StatelessWidget {
  final _FriendListMode mode;
  final ValueChanged<_FriendListMode> onModeChanged;

  const _FriendActivitySummary({
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '친구가 참여하는 대회와 클럽 일정을 모아봤어요.',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _SummaryButton(
                  icon: Icons.groups_rounded,
                  label: '친구가 가입한 클럽보기',
                  count: '3',
                  color: cs.primary,
                  selected: mode == _FriendListMode.clubs,
                  onTap: () => onModeChanged(_FriendListMode.clubs),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SummaryButton(
                  icon: Icons.emoji_events_rounded,
                  label: '친구가 신청한 대회보기',
                  count: '2',
                  color: cs.primary,
                  selected: mode == _FriendListMode.tournaments,
                  onTap: () => onModeChanged(_FriendListMode.tournaments),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? color : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? color : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? Colors.white : color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected ? Colors.white : cs.onSurface,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected ? Colors.white : color,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendList extends StatelessWidget {
  final _FriendListMode mode;

  const _FriendList({required this.mode});

  @override
  Widget build(BuildContext context) {
    final children = switch (mode) {
      _FriendListMode.clubs => const [
          _FriendActivityCard(
            type: _FriendActivityType.club,
            friendName: '준호',
            title: '서울 풋살 러너스',
            meta: '송파 · 주말 저녁 정기 모임',
            status: '클럽 멤버',
          ),
          SizedBox(height: AppSpacing.sm),
          _FriendActivityCard(
            type: _FriendActivityType.club,
            friendName: '서연',
            title: '광주 테니스 크루',
            meta: '광주 · 수/토 운동',
            status: '운영진',
          ),
          SizedBox(height: AppSpacing.sm),
          _FriendActivityCard(
            type: _FriendActivityType.club,
            friendName: '민지',
            title: '수도권 풋살 위클리',
            meta: '서울/경기 · 평일 야간',
            status: '클럽 멤버',
          ),
        ],
      _FriendListMode.tournaments => const [
          _FriendActivityCard(
            type: _FriendActivityType.tournament,
            friendName: '민지',
            title: '2026 생활체육 서울시민리그 풋살리그',
            meta: '6월 21일 · 서울시민리그 공식 경기장',
            status: '대회 신청 완료',
          ),
          SizedBox(height: AppSpacing.sm),
          _FriendActivityCard(
            type: _FriendActivityType.tournament,
            friendName: '지훈',
            title: '광주 오픈 테니스 챌린지',
            meta: '6월 14일 · 광주 테니스협회',
            status: '참가 확정',
          ),
        ],
      _FriendListMode.activity => const [
          _FriendActivityCard(
            type: _FriendActivityType.tournament,
            friendName: '민지',
            title: '2026 생활체육 서울시민리그 풋살리그',
            meta: '6월 21일 · 서울시민리그 공식 경기장',
            status: '대회 신청 완료',
          ),
          SizedBox(height: AppSpacing.sm),
          _FriendActivityCard(
            type: _FriendActivityType.club,
            friendName: '준호',
            title: '서울 풋살 러너스 정기 모임',
            meta: '6월 26일 · 잠실 풋살파크',
            status: '참석 예정',
          ),
        ],
    };

    final title = switch (mode) {
      _FriendListMode.clubs => '친구가 가입한 클럽',
      _FriendListMode.tournaments => '친구가 신청한 대회',
      _FriendListMode.activity => '다가오는 친구 일정',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}

class _FriendActivityCard extends StatelessWidget {
  final _FriendActivityType type;
  final String friendName;
  final String title;
  final String meta;
  final String status;

  const _FriendActivityCard({
    required this.type,
    required this.friendName,
    required this.title,
    required this.meta,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTournament = type == _FriendActivityType.tournament;
    final color = cs.primary;
    final icon =
        isTournament ? Icons.emoji_events_rounded : Icons.groups_rounded;
    final label = isTournament ? '대회' : '클럽';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$friendName님',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
