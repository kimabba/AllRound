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
    this.seq,
  });

  final Tournament tournament;
  final bool isFavorite;
  final bool isMyGrade;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final bool compact;
  // 목록 내 순번(1,2,3…). 캘린더 목록에서만 전달(favorites/chat엔 미표시).
  final int? seq;

  static final _df = DateFormat('M/d (E)', 'ko');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = _status(context);
    final deadlineText = _deadlineText();
    final date = tournament.startDate;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 86 : 104),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '대회',
                      style: tt.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd').format(date),
                      style: tt.headlineLarge?.copyWith(
                        height: 1,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text('${date.month}월', style: tt.labelSmall),
                  ],
                ),
              ),
              Container(width: 1, height: 60, color: cs.outlineVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tournament.title,
                      style: tt.titleMedium,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _locationText().isEmpty ? _dateText() : _locationText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Text(
                          status.label,
                          style: tt.labelSmall?.copyWith(
                            color: status.foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (deadlineText != null) ...[
                          Text(
                            '신청',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            deadlineText,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (isMyGrade)
                          Text(
                            '내 등급',
                            style: tt.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onFavoriteToggle != null)
                SizedBox.square(
                  dimension: 44,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 21,
                    tooltip: isFavorite ? '관심 해제' : '관심 대회 저장',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onFavoriteToggle!();
                    },
                    icon: Icon(
                      isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                      color: isFavorite ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateText() =>
      tournamentDateText(tournament.startDate, tournament.endDate, _df.format);

  /// 신청 마감일 + D-day. 마감일이 없으면 null(줄 자체를 그리지 않음).
  String? _deadlineText() {
    final d = tournament.applicationDeadline;
    if (d == null) return null;
    final date = _df.format(d);
    // 종료 상태면 마감일이 미래여도 D-day 대신 마감으로 표시.
    if (tournament.status == 'closed' || tournament.status == 'cancelled') {
      return '$date · 마감';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = d.difference(today).inDays;
    if (daysLeft < 0) return '$date · 마감';
    if (daysLeft == 0) return '$date · D-day';
    return '$date · D-$daysLeft';
  }

  String _locationText() =>
      locationText(tournament.location, tournament.region);

  _StatusBadgeData _status(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // closed/cancelled는 마감일과 무관하게 종료 상태 — 상세·신청바와 기준 통일.
    if (tournament.status == 'closed' || tournament.status == 'cancelled') {
      return _StatusBadgeData(
        label: _statusLabel(tournament.status),
        foreground: cs.onSurfaceVariant,
      );
    }
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
        );
      }
      if (daysLeft <= 3) {
        return _StatusBadgeData(
          label: '마감임박',
          foreground: cs.error,
        );
      }
    }
    // deadline이 없어도 start_date가 지났으면 마감 처리
    final today = DateTime.now();
    final startPassed = tournament.startDate.isBefore(
      DateTime(today.year, today.month, today.day),
    );
    if (startPassed && tournament.status == 'published') {
      return _StatusBadgeData(
        label: '마감',
        foreground: cs.onSurfaceVariant,
      );
    }
    return _StatusBadgeData(
      label: _statusLabel(tournament.status),
      foreground: tournament.sport == 'tennis'
          ? cs.onTertiaryContainer
          : cs.onSecondaryContainer,
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

class _StatusBadgeData {
  const _StatusBadgeData({
    required this.label,
    required this.foreground,
  });

  final String label;
  final Color foreground;
}
