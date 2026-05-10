import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final Color? selectedColor;

  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leadingIcon,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final Color bg = selected
        ? (selectedColor ?? cs.primaryContainer)
        : cs.surfaceContainerHigh;
    final Color fg = selected
        ? (selectedColor != null
            ? cs.onSurface
            : cs.onPrimaryContainer)
        : cs.onSurfaceVariant;

    return AnimatedContainer(
      duration: AppDuration.short3,
      curve: AppCurves.standard,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 16, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(label, style: tt.labelMedium?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
