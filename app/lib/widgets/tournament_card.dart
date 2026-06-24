import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/tournament.dart';
import '../models/tournament_card_info.dart';
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
            // Row 1: 상태 배지 + (내 등급) + D-day 배지
            // 날짜는 라벨 없이 섞이면 마감/대회일을 혼동시키므로 여기서 빼고,
            // 아래 정보 블록에서 라벨과 함께 명시한다.
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
                const Spacer(),
                if (_dday.isNotEmpty)
                  _StatusChip(
                    label: _dday,
                    foreground: cs.onError,
                    background: cs.error,
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
            const SizedBox(height: AppSpacing.md),

            // 정보 블록: 라벨로 명확히 구분한 3줄(대회일 · 신청 마감 · 위치).
            // "대회"와 "신청"을 각각 라벨링해 날짜 혼동을 없앤다.
            _InfoLine(
              icon: Icons.event_rounded,
              label: '대회',
              value: _dateText(),
            ),
            const SizedBox(height: 4),
            if (_deadlineText().isNotEmpty) ...[
              _InfoLine(
                icon: Icons.how_to_reg_rounded,
                label: '신청',
                value: _deadlineText(),
                // 마감일은 신청 의사결정에 핵심 → 살짝 강조(임박이면 error색).
                emphasize: true,
                emphasizeColor: _deadlineSoon ? cs.error : null,
              ),
              const SizedBox(height: 4),
            ],
            if (_locationText().isNotEmpty)
              // 위치는 사용자에게 매우 중요 → place 아이콘 + 본문 크기로 눈에 띄게.
              Row(
                children: [
                  Icon(Icons.place_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _locationText(),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),

            // Row 5: 등급 + 즐겨찾기
            Row(
              children: [
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

  DeadlineInfo get _deadlineInfo =>
      DeadlineInfo.compute(tournament.applicationDeadline, DateTime.now());

  /// D-day 배지 텍스트(1~7일·당일에만 노출).
  String get _dday => _deadlineInfo.ddayBadge;

  /// 마감 임박(D-Day 또는 7일 이내) 여부 — 신청 줄 강조 색 판정에 사용.
  bool get _deadlineSoon =>
      _deadlineInfo.status == DeadlineStatus.today ||
      _deadlineInfo.status == DeadlineStatus.soon;

  String _dateText() =>
      tournamentDateText(tournament.startDate, tournament.endDate, _df.format);

  String _deadlineText() =>
      applicationDeadlineText(tournament.applicationDeadline, _df.format);

  String _locationText() =>
      locationText(tournament.location, tournament.region);

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

}

/// 라벨이 붙은 정보 한 줄: [아이콘] [라벨칩] 값.
/// "대회 / 신청"을 명시 라벨로 구분해 날짜 혼동을 없앤다. 값이 길면 ellipsis.
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.emphasizeColor,
  });

  final IconData icon;
  final String label;
  final String value;

  /// true면 값 텍스트를 살짝 강조(굵게 + [emphasizeColor] 적용).
  final bool emphasize;
  final Color? emphasizeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final valueColor =
        emphasizeColor ?? (emphasize ? cs.onSurface : cs.onSurfaceVariant);
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        // 라벨: 작은 캡슐로 "무엇에 대한 날짜인지" 즉시 인지시킨다.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: tt.labelSmall?.copyWith(
              color: valueColor,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
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
