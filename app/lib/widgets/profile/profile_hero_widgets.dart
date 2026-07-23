import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar
// ────────────────────────────────────────────────────────────

class ProfileHeroSliver extends StatelessWidget {
  final String initial;
  final String title; // 앱 활동 표시명(닉네임 우선)
  final String subtitle; // 이메일
  final String? infoLine; // 실명·나이 (본인만)
  final AsyncValue<List<UserSport>> sports;
  final AsyncValue<List<UserTennisOrg>> tennisOrgs;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final VoidCallback onAvatarTap;
  final VoidCallback onNotificationsTap;
  final int unreadNotificationCount;
  final VoidCallback onMoreTap;

  const ProfileHeroSliver({
    super.key,
    required this.initial,
    required this.title,
    required this.subtitle,
    required this.infoLine,
    required this.sports,
    required this.tennisOrgs,
    required this.avatarBytes,
    required this.avatarUrl,
    required this.onAvatarTap,
    required this.onNotificationsTap,
    required this.unreadNotificationCount,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverAppBar(
      expandedHeight: 286,
      pinned: true,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      title: Text(
        'MY',
        style: tt.titleLarge?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        Badge(
          isLabelVisible: unreadNotificationCount > 0,
          label: Text(
            unreadNotificationCount > 99 ? '99+' : '$unreadNotificationCount',
          ),
          child: IconButton(
            tooltip: unreadNotificationCount > 0
                ? '읽지 않은 알림 $unreadNotificationCount개'
                : '알림함',
            onPressed: onNotificationsTap,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        IconButton(
          tooltip: '전체 메뉴',
          onPressed: onMoreTap,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            kToolbarHeight + AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ProfileHeaderContent(
                initial: initial,
                title: title,
                subtitle: subtitle,
                infoLine: infoLine,
                sports: sports,
                avatarBytes: avatarBytes,
                avatarUrl: avatarUrl,
                onAvatarTap: onAvatarTap,
              ),
              const SizedBox(height: AppSpacing.xl),
              StatsGrid(sports: sports, tennisOrgs: tennisOrgs),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileHeaderContent extends StatelessWidget {
  const ProfileHeaderContent({
    super.key,
    required this.initial,
    required this.title,
    required this.subtitle,
    required this.infoLine,
    required this.sports,
    required this.avatarBytes,
    required this.avatarUrl,
    required this.onAvatarTap,
  });

  final String initial;
  final String title;
  final String subtitle;
  final String? infoLine;
  final AsyncValue<List<UserSport>> sports;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
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
    final normalizedAvatarUrl = avatarUrl?.trim();
    final ImageProvider<Object>? avatarImage = avatarBytes != null
        ? MemoryImage(avatarBytes!)
        : normalizedAvatarUrl == null || normalizedAvatarUrl.isEmpty
            ? null
            : NetworkImage(normalizedAvatarUrl);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  image: avatarImage == null
                      ? null
                      : DecorationImage(
                          image: avatarImage,
                          fit: BoxFit.cover,
                        ),
                ),
                alignment: Alignment.center,
                child: avatarImage == null
                    ? Text(
                        initial,
                        style: tt.headlineMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
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
                    color: cs.surface,
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: cs.onSurfaceVariant,
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
                title.isEmpty ? '사용자' : title,
                style: tt.titleLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (infoLine != null) ...[
                const SizedBox(height: 2),
                Text(
                  infoLine!,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
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

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: StatCard(
                value: '$sportCount',
                label: '등록 종목',
              ),
            ),
            VerticalDivider(width: 1, color: cs.outlineVariant),
            Expanded(
              child: StatCard(
                value: '$orgCount',
                label: '소속 협회',
              ),
            ),
            VerticalDivider(width: 1, color: cs.outlineVariant),
            Expanded(
              child: StatCard(
                value: primary == null ? '-' : sportLabelFromString(primary),
                label: '기본 필터',
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.compact = false,
  });

  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        children: [
          Text(
            value,
            style: (compact ? tt.labelLarge : tt.titleLarge)?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
