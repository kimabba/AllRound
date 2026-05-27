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
    this.onTap,
    this.onFavoriteToggle,
  });

  final Tournament tournament;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  static final _df = DateFormat('M월 d일 (E)', 'ko');
  static final _fee = NumberFormat.decimalPattern('ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = tournament.sport == 'tennis';
    final accentColor = isTennis ? cs.tertiary : cs.secondary;
    final accentContainer = isTennis
        ? cs.tertiaryContainer
        : cs.secondaryContainer;
    final onAccentContainer = isTennis
        ? cs.onTertiaryContainer
        : cs.onSecondaryContainer;
    final grades = tournament.eligibleGrades.map(gradeLabel).join(' · ');
    final status = _status(context);
    final feeText = _entryFeeText();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        variant: AppCardVariant.elevated,
        padding: const EdgeInsets.all(AppSpacing.lg),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _Badge(
                        label: status.label,
                        foreground: status.foreground,
                        background: status.background,
                      ),
                      _Badge(
                        label: grades.isEmpty ? '전체 등급' : grades,
                        foreground: cs.primary,
                        background: cs.primaryContainer,
                      ),
                      _Badge(
                        label: sportLabelFromString(tournament.sport),
                        foreground: onAccentContainer,
                        background: accentContainer,
                      ),
                    ],
                  ),
                ),
                if (onFavoriteToggle != null)
                  _FavoriteButton(
                    isFavorite: isFavorite,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onFavoriteToggle!();
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              tournament.title,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (tournament.organizer != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                tournament.organizer!,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaLine(
                  icon: Icons.calendar_today_rounded,
                  label: _dateText(),
                ),
                if (tournament.location != null || tournament.region != null)
                  _MetaLine(
                    icon: Icons.place_rounded,
                    label: [
                      tournament.region,
                      tournament.location,
                    ].whereType<String>().join(' · '),
                  ),
                if (feeText != null)
                  _MetaLine(icon: Icons.payments_outlined, label: feeText),
              ],
            ),
            if (tournament.applicationDeadline != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppRadius.pill,
                      child: LinearProgressIndicator(
                        value: _deadlineProgress(),
                        minHeight: 6,
                        backgroundColor: cs.outlineVariant,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    _deadlineText(),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateText() {
    final start = _df.format(tournament.startDate);
    final end = tournament.endDate;
    if (end == null || _isSameDay(tournament.startDate, end)) return start;
    return '$start - ${_df.format(end)}';
  }

  String? _entryFeeText() {
    final fee = tournament.entryFee;
    if (fee == null || fee <= 0) return null;
    final unit = tournament.entryFeeUnit == 'per_person' ? '인당' : '팀당';
    return '$unit ${_fee.format(fee)}원';
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
    if (daysLeft < 0) return '마감';
    if (daysLeft == 0) return 'D-Day';
    return 'D-$daysLeft';
  }

  double _deadlineProgress() {
    final deadline = tournament.applicationDeadline;
    if (deadline == null) return 0;
    final totalDays = deadline.difference(tournament.startDate).inDays.abs();
    if (totalDays <= 0) return 1;
    final daysLeft = deadline.difference(DateTime.now()).inDays;
    return (1 - (daysLeft / totalDays)).clamp(0, 1).toDouble();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w900,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          key: ValueKey(isFavorite),
          isFavorite ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
          color: isFavorite ? cs.primary : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
    );
  }
}
