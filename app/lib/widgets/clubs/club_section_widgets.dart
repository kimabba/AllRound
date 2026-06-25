import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class SimpleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SimpleSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SimplePanel extends StatelessWidget {
  final Widget child;

  const SimplePanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class SimpleActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final Color color;
  final VoidCallback? onTap;

  const SimpleActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary),
                ),
                child: Text(
                  action!,
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
