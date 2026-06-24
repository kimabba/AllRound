import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/tournament.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import 'app_card.dart';

class TournamentCard extends StatelessWidget {
  const TournamentCard({
    super.key,
    required this.tournament,
    this.isFavorite = false,
    this.isMyGrade = false,
    this.onTap,
    this.onFavoriteToggle,
    this.compact = false,
  });

  final Tournament tournament;
  final bool isFavorite;
  final bool isMyGrade;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final bool compact;

  static final _df = DateFormat('M/d (E)', 'ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = _status(context);
    // 출전 부서: 카드는 한 줄이라 앞 3개만 보이고 나머지는 "외 N개"로 명시한다.
    // (전에는 take(3) 으로 조용히 잘려 상세 화면의 전체 부서와 어긋나 보였다.)
    final allGrades = tournament.eligibleGrades
        .map((g) => divisionLabel(g) != g ? divisionLabel(g) : gradeLabel(g))
        .toSet()
        .toList();
    final extraGrades = allGrades.length - 3;
    final grades = extraGrades > 0
        ? '${allGrades.take(3).join(' · ')} 외 $extraGrades개'
        : allGrades.join(' · ');
    final futsalCategory = tournament.sport == 'futsal'
        ? futsalEventCategoryLabel(tournament.futsalEventCategory)
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        variant: AppCardVariant.elevated,
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: 상태 + D-day + 날짜
            Row(
              children: [
                _StatusChip(
                  label: status.label,
                  foreground: status.foreground,
                  background: status.background,
                ),
                if (isMyGrade) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _StatusChip(
                    label: '내 등급',
                    foreground: cs.primary,
                    background: cs.primaryContainer,
                  ),
                ],
                if (_deadlineText().isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _deadlineText(),
                    style: tt.labelSmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const Spacer(),
                Icon(Icons.calendar_today_rounded,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _dateText(),
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Row 2: 타이틀
            Text(
              tournament.title,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Row 3: 주최
            if (!compact && tournament.organizer != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tournament.organizer!,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (futsalCategory.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _CategoryChip(label: futsalCategory),
                  ],
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),

            // Row 4: 지역 + 등급 + 즐겨찾기
            Row(
              children: [
                if (tournament.region != null) ...[
                  Icon(Icons.place_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    tournament.region!,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    grades.isEmpty ? '전체 등급' : '🏆 $grades',
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onFavoriteToggle != null)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onFavoriteToggle!();
                    },
                    child: Icon(
                      isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      size: 22,
                      color: isFavorite ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateText() {
    final start = _df.format(tournament.startDate);
    final end = tournament.endDate;
    if (end == null || _isSameDay(tournament.startDate, end)) return start;
    return '$start~${_df.format(end)}';
  }

  _StatusBadgeData _status(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deadline = tournament.applicationDeadline;
    if (deadline != null) {
      final today = DateTime.now();
      final daysLeft = deadline
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
      if (daysLeft < 0) {
        return _StatusBadgeData(
          label: '마감',
          foreground: cs.onSurfaceVariant,
          background: cs.surfaceContainerHighest,
        );
      }
      if (daysLeft <= 3) {
        return const _StatusBadgeData(
          label: '마감임박',
          foreground: Color(0xFFDC2626),
          background: Color(0xFFFEE2E2),
        );
      }
    }
    // deadline이 없어도 start_date가 지났으면 마감 처리
    final today = DateTime.now();
    final startPassed = tournament.startDate
        .isBefore(DateTime(today.year, today.month, today.day));
    if (startPassed && tournament.status == 'published') {
      return _StatusBadgeData(
        label: '마감',
        foreground: cs.onSurfaceVariant,
        background: cs.surfaceContainerHighest,
      );
    }
    return _StatusBadgeData(
      label: _statusLabel(tournament.status),
      foreground: tournament.sport == 'tennis'
          ? cs.onTertiaryContainer
          : cs.onSecondaryContainer,
      background: tournament.sport == 'tennis'
          ? cs.tertiaryContainer
          : cs.secondaryContainer,
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'published' => '모집중',
      'draft' => '검토중',
      'closed' => '마감',
      'cancelled' => '취소',
      _ => status,
    };
  }

  String _deadlineText() {
    final deadline = tournament.applicationDeadline;
    if (deadline == null) return '';
    final today = DateTime.now();
    final daysLeft = deadline
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (daysLeft < 0) return '';
    if (daysLeft == 0) return 'D-Day';
    if (daysLeft <= 7) return 'D-$daysLeft';
    return '';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  const _StatusChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _StatusBadgeData {
  const _StatusBadgeData({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;
}
