import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class AppHeroSection extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final IconData icon;

  const AppHeroSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.icon = Icons.sports_tennis_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: AppRadius.hero,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Text(
                eyebrow,
                style: tt.labelMedium?.copyWith(
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: tt.headlineMedium?.copyWith(color: cs.onSurface),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onCta, child: Text(ctaLabel!)),
          ],
        ],
      ),
    );
  }
}
