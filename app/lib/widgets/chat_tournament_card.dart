import 'package:flutter/material.dart';

import '../models/chat_ui.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
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

  static const _actions = ['상세 알려줘', '신청 방법 알려줘', '마감 확인해줘'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = item.sport == 'tennis';
    final accent = isTennis ? cs.tertiary : cs.secondary;

    final meta = <String>[
      sportLabelFromString(item.sport),
      if (item.region != null) item.region!,
      item.endDate != null && item.endDate != item.startDate
          ? '${item.startDate} ~ ${item.endDate}'
          : item.startDate,
      if (item.entryFee != null) '${item.entryFee}원',
      if (item.format != null) item.format!,
    ].where((s) => s.isNotEmpty).join(' · ');

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
          const SizedBox(height: AppSpacing.xs),
          Text(
            meta,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final action in _actions)
                OutlinedButton(
                  onPressed: () => onAction(action, item.id),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                  ),
                  child: Text(action, style: tt.labelMedium),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
