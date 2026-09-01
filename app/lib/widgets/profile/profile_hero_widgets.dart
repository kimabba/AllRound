import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';

// ────────────────────────────────────────────────────────────
// Hero SliverAppBar
// ────────────────────────────────────────────────────────────

class ProfileHeroSliver extends StatelessWidget {
  final String initial;
  final String title; // 앱 활동 표시명(닉네임 우선)
  final String subtitle; // 이메일
  final String? infoLine; // 실명·나이 (본인만)
  // 종목·협회는 본문에서만 표시하지만 기존 호출부 호환은 유지한다.
  final AsyncValue<List<UserSport>>? sports;
  final AsyncValue<List<UserTennisOrg>>? tennisOrgs;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final VoidCallback onAvatarTap;
  final VoidCallback onNotificationsTap;
  final int unreadNotificationCount;
  final VoidCallback? onMoreTap;

  const ProfileHeroSliver({
    super.key,
    required this.initial,
    required this.title,
    required this.subtitle,
    required this.infoLine,
    this.sports,
    this.tennisOrgs,
    required this.avatarBytes,
    required this.avatarUrl,
    required this.onAvatarTap,
    required this.onNotificationsTap,
    required this.unreadNotificationCount,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topSafeArea = MediaQuery.paddingOf(context).top;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // 기본 화면에서는 프로필 카드의 빈 상단을 줄인다. 큰 글자와 iPhone 안전영역은
    // 내용이 잘리지 않도록 줄인 높이를 다시 보충한다.
    final compactReduction = 32.0 * (2.0 - textScale).clamp(0.0, 1.0);
    final safeAreaCompensation = topSafeArea.clamp(0.0, compactReduction);
    final expandedHeight = 238.0 +
        AppSpacing.sm -
        compactReduction +
        safeAreaCompensation +
        ((textScale - 1).clamp(0.0, 1.0) * 180.0);
    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: false,
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
        const SizedBox(width: AppSpacing.sm),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            topSafeArea + kToolbarHeight + AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: AppRadius.hero,
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProfileHeaderContent(
                      initial: initial,
                      title: title,
                      subtitle: subtitle,
                      infoLine: infoLine,
                      avatarBytes: avatarBytes,
                      avatarUrl: avatarUrl,
                      onAvatarTap: onAvatarTap,
                    ),
                  ],
                ),
              ],
            ),
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
    required this.avatarBytes,
    required this.avatarUrl,
    required this.onAvatarTap,
  });

  final String initial;
  final String title;
  final String subtitle;
  final String? infoLine;
  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
                  color: cs.onPrimary.withValues(alpha: 0.14),
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
                          color: cs.onPrimary,
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
                    color: cs.onPrimary,
                    border: Border.all(
                      color: cs.onPrimary.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
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
                title.isEmpty ? '사용자' : title,
                style: tt.titleLarge?.copyWith(
                  color: cs.onPrimary,
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
                    color: cs.onPrimary.withValues(alpha: 0.72),
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
                    color: cs.onPrimary.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
