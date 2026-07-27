import 'package:flutter/material.dart';
import '../theme/tokens.dart';

enum AppCardVariant { filled, outlined, elevated }

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final AppCardVariant variant;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.variant = AppCardVariant.filled,
    this.padding = AppSpacing.cardInner,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final BorderRadius radius = borderRadius ?? AppRadius.card;

    final BoxDecoration decoration = BoxDecoration(
      color: backgroundColor ??
          switch (variant) {
            AppCardVariant.filled => cs.surfaceContainerLow,
            AppCardVariant.outlined => cs.surface,
            AppCardVariant.elevated => cs.surfaceContainerLowest,
          },
      borderRadius: radius,
      border: variant == AppCardVariant.filled
          ? null
          : Border.all(color: borderColor ?? cs.outlineVariant),
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
