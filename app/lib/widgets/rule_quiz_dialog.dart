import 'package:flutter/material.dart';

import '../models/rule_quiz.dart';
import '../theme/tokens.dart';

Future<void> showRuleQuizDialog(BuildContext context, RuleQuiz quiz) {
  var selectedIndex = -1;
  var revealed = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          title: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '오늘의 룰 퀴즈',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quiz.question,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var index = 0; index < quiz.options.length; index++) ...[
                  _QuizOption(
                    number: index + 1,
                    label: quiz.options[index],
                    selected: selectedIndex == index,
                    correct: revealed && quiz.correctIndex == index,
                    wrong: revealed &&
                        selectedIndex == index &&
                        quiz.correctIndex != index,
                    onTap: revealed
                        ? null
                        : () => setDialogState(() => selectedIndex = index),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (revealed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: selectedIndex == quiz.correctIndex
                          ? cs.primaryContainer
                          : cs.errorContainer,
                      borderRadius: AppRadius.card,
                    ),
                    child: Text(
                      quiz.explanation,
                      style: tt.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(revealed ? '닫기' : '취소'),
            ),
            if (!revealed)
              FilledButton(
                onPressed: selectedIndex < 0
                    ? null
                    : () => setDialogState(() => revealed = true),
                child: const Text('정답 확인'),
              ),
          ],
        );
      },
    ),
  );
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.number,
    required this.label,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = correct
        ? cs.secondary
        : wrong
            ? cs.error
            : selected
                ? cs.primary
                : cs.outlineVariant;
    final background = correct
        ? cs.secondaryContainer
        : wrong
            ? cs.errorContainer
            : selected
                ? cs.primaryContainer
                : cs.surfaceContainerLow;

    return Material(
      color: background,
      borderRadius: AppRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(
              color: color,
              width: selected || correct || wrong ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: color,
                child: Text(
                  '$number',
                  style: tt.labelSmall?.copyWith(
                    color: correct || wrong || selected
                        ? Colors.white
                        : cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (correct) Icon(Icons.check_rounded, color: cs.secondary),
              if (wrong) Icon(Icons.close_rounded, color: cs.error),
            ],
          ),
        ),
      ),
    );
  }
}
