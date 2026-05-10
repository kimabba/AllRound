import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class AppListSection extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;
  final double itemGap;

  const AppListSection({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    required this.children,
    this.itemGap = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(child: Text(title, style: tt.titleLarge)),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
        for (int i = 0; i < children.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: children[i],
          ),
          if (i != children.length - 1) SizedBox(height: itemGap),
        ],
      ],
    );
  }
}
