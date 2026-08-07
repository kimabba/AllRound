import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/chat_state.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';

/// 다른 화면을 보는 동안에도 진행 중인 볼보이 대화 상태를 보여주는 미니 바.
class MiniBallboyBar extends ConsumerWidget {
  const MiniBallboyBar({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      key: AllRoundE2EKeys.miniChatBar,
      color: cs.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '볼보이 대화 다시 열기',
                      hint: chat.miniBarPreview,
                      onTap: onOpen,
                      child: ExcludeSemantics(
                        child: InkWell(
                          key: AllRoundE2EKeys.miniChatOpen,
                          onTap: onOpen,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  'BB',
                                  style: tt.labelMedium?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '볼보이',
                                      style: tt.labelMedium?.copyWith(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      chat.miniBarPreview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: cs.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '볼보이 미니 바 닫기',
                    child: IconButton(
                      key: AllRoundE2EKeys.miniChatClose,
                      tooltip: '미니 바 닫기',
                      onPressed: ref.read(chatProvider).hideMiniBar,
                      icon: const Icon(Icons.close_rounded),
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (chat.busy)
              LinearProgressIndicator(
                minHeight: 2,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerLow,
              ),
          ],
        ),
      ),
    );
  }
}
