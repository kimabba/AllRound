import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum AppCardVariant { filled, outlined, elevated }

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final AppCardVariant variant;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.variant = AppCardVariant.filled,
    this.padding = AppSpacing.cardInner,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final BorderRadius radius = borderRadius ?? AppRadius.card;

    final BoxDecoration decoration = BoxDecoration(
      color: switch (variant) {
        AppCardVariant.filled => cs.surfaceContainerLow,
        AppCardVariant.outlined => cs.surface,
        AppCardVariant.elevated => cs.surfaceContainerLow,
      },
      borderRadius: radius,
      border: variant == AppCardVariant.outlined
          ? Border.all(color: cs.outlineVariant)
          : null,
      boxShadow: switch (variant) {
        AppCardVariant.elevated => isLight ? AppShadows.elevated : null,
        AppCardVariant.filled => isLight ? AppShadows.card : null,
        AppCardVariant.outlined => null,
      },
    );

    final Widget content = Padding(padding: padding, child: child);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: decoration,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: content,
              ),
      ),
    );
  }
}
