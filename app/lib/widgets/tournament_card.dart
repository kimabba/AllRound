import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/tournament.dart';
import '../models/tournament_card_info.dart';
import '../theme/tokens.dart';

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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : cs.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(color: cs.outlineVariant),
            boxShadow: isLight ? AppShadows.card : null,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            color:
                                isFavorite ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    tournament.title,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _InfoLine(
                    icon: Icons.event_rounded,
                    label: '대회',
                    value: _dateText(),
                  ),
                  const SizedBox(height: 4),
                  if (_locationText().isNotEmpty)
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _dateText() =>
      tournamentDateText(tournament.startDate, tournament.endDate, _df.format);

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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
