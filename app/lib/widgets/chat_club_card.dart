import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/chat_ui.dart';
import '../theme/tokens.dart';
import '../utils/club_labels.dart';
import '../widgets/app_card.dart';

/// 채팅 안에 렌더되는 클럽 카드. raw id 는 표시하지 않는다.
/// 액션 버튼은 (message, entityId) 콜백으로 후속 chat 요청을 위임한다.
class ChatClubCard extends StatelessWidget {
  final ClubChatCardItem item;
  final void Function(String message, String entityId) onAction;

  const ChatClubCard({
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

    final sportLabel = isTennis ? '테니스' : '풋살';
    final metaParts = <String>[
      sportLabel,
      if (item.region != null && item.region!.trim().isNotEmpty)
        item.region!.trim(),
      '멤버 ${item.memberCount}명',
    ];

    final description = item.description?.trim();
    final genderLabel = clubGenderLabel(item.genderPreference);
    final chips = <String>[
      if (item.monthlyFee != null) clubMonthlyFeeLabel(item.monthlyFee!),
      if (genderLabel.isNotEmpty) genderLabel,
      if (item.meetingDays.isNotEmpty) item.meetingDays.join(' · '),
    ];

    return AppCard(
      variant: AppCardVariant.outlined,
      onTap: () => context.push('/clubs/${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            metaParts.join(' · '),
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(height: 1.4),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      chip,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onAction('이 클럽 상세 알려줘', item.id),
                  child: const Text('상세 보기'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push('/clubs/${item.id}'),
                  child: const Text('클럽 방문하기'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
