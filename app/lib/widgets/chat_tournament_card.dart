import 'package:flutter/material.dart';

import '../models/chat_ui.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';

/// 채팅 안에 렌더되는 대회 카드. raw id 는 표시하지 않는다.
/// 액션 버튼은 (message, entityId) 콜백으로 후속 chat 요청을 위임한다.
class ChatTournamentCard extends StatelessWidget {
  final TournamentChatCardItem item;
  final void Function(String message, String entityId) onAction;

  const ChatTournamentCard({
    super.key,
    required this.item,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = item.sport == 'tennis';
    final accent = isTennis ? cs.tertiary : cs.secondary;

    final dateText = item.endDate != null && item.endDate != item.startDate
        ? '${item.startDate} ~ ${item.endDate}'
        : item.startDate;

    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTennis
                    ? Icons.sports_tennis_rounded
                    : Icons.sports_soccer_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: '일정',
            value: dateText,
            cs: cs,
            tt: tt,
          ),
          if (item.location != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InfoRow(
              icon: Icons.location_on_rounded,
              label: '장소',
              value: item.location!,
              cs: cs,
              tt: tt,
            ),
          ],
          if (item.applicationDeadline != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InfoRow(
              icon: Icons.timer_rounded,
              label: '신청 마감',
              value: item.applicationDeadline!,
              cs: cs,
              tt: tt,
            ),
          ],
          if (item.entryFee != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _InfoRow(
              icon: Icons.payments_rounded,
              label: '참가비',
              value: '${item.entryFee}원',
              cs: cs,
              tt: tt,
            ),
          ],
          if (item.regulationFields.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _RegulationSummary(
              fields: item.regulationFields,
              cs: cs,
              tt: tt,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onAction('상세 알려줘', item.id),
              child: const Text('상세 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 요강 요약 — 라벨/값 칩 2~3개를 작게 wrap 으로 표시. 카드가 길어지지 않게 한다.
class _RegulationSummary extends StatelessWidget {
  final List<RegulationField> fields;
  final ColorScheme cs;
  final TextTheme tt;

  const _RegulationSummary({
    required this.fields,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final f in fields)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: AppRadius.pill,
            ),
            child: RichText(
              text: TextSpan(
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                children: [
                  TextSpan(text: '${f.label} '),
                  TextSpan(
                    text: f.value,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label  ',
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
