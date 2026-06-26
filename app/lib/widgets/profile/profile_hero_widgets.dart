import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_card.dart';

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar
// ────────────────────────────────────────────────────────────

class ProfileHeroSliver extends StatelessWidget {
  final String initial;
  final String email;
  final AsyncValue<List<UserSport>> sports;
  final AsyncValue<List<UserTennisOrg>> tennisOrgs;
  final Uint8List? avatarBytes;
  final VoidCallback onAvatarTap;

  const ProfileHeroSliver({
    super.key,
    required this.initial,
    required this.email,
    required this.sports,
    required this.tennisOrgs,
    required this.avatarBytes,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      expandedHeight: 306,
      pinned: true,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      title: Text(
        'MY',
        style: tt.titleLarge?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, const Color(0xFF3B5BDB), cs.secondary],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                kToolbarHeight + AppSpacing.md,
                AppSpacing.lg,
                112,
              ),
              child: ProfileHeaderContent(
                initial: initial,
                email: email,
                sports: sports,
                avatarBytes: avatarBytes,
                onAvatarTap: onAvatarTap,
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: StatsGrid(sports: sports, tennisOrgs: tennisOrgs),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileHeaderContent extends StatelessWidget {
  const ProfileHeaderContent({
    super.key,
    required this.initial,
    required this.email,
    required this.sports,
    required this.avatarBytes,
    required this.onAvatarTap,
  });

  final String initial;
  final String email;
  final AsyncValue<List<UserSport>> sports;
  final Uint8List? avatarBytes;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final primary = sports.maybeWhen(
      data: (items) => items.where((s) => s.isPrimary).firstOrNull,
      orElse: () => null,
    );
    final sportCount = sports.maybeWhen(data: (l) => l.length, orElse: () => 0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
                backgroundImage:
                    avatarBytes == null ? null : MemoryImage(avatarBytes!),
                child: avatarBytes == null
                    ? Text(
                        initial,
                        style: tt.headlineMedium?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.onPrimary,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.cardFor(Theme.of(context).brightness),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: cs.primary,
                    size: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                email.isEmpty ? '사용자' : email,
                style: tt.titleLarge?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  HeroChip(
                    label: primary == null
                        ? '종목 미등록'
                        : sportLabelFromString(primary.sport),
                  ),
                  if (primary != null)
                    HeroChip(label: gradeLabel(primary.grade)),
                  HeroChip(label: '$sportCount개 종목'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HeroChip extends StatelessWidget {
  const HeroChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.onPrimary.withValues(alpha: 0.18),
        borderRadius: AppRadius.pill,
        border: Border.all(color: cs.onPrimary.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.sports, required this.tennisOrgs});

  final AsyncValue<List<UserSport>> sports;
  final AsyncValue<List<UserTennisOrg>> tennisOrgs;

  @override
  Widget build(BuildContext context) {
    final sportCount = sports.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    final orgCount = tennisOrgs.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    final primary = sports.maybeWhen(
      data: (items) => items.where((s) => s.isPrimary).firstOrNull?.sport,
      orElse: () => null,
    );

    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.sports_score_rounded,
            value: '$sportCount',
            label: '등록 종목',
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: StatCard(
            icon: Icons.emoji_events_rounded,
            value: '$orgCount',
            label: '소속 협회',
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: StatCard(
            icon: Icons.tune_rounded,
            value: primary == null ? '-' : sportLabelFromString(primary),
            label: '기본 필터',
            color: Theme.of(context).colorScheme.primary,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: (compact ? tt.labelLarge : tt.titleLarge)?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w900,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
