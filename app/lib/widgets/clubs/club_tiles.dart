import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';
import '../../utils/club_labels.dart';
import '../../utils/grade_labels.dart';
import '../../widgets/app_empty_state.dart';
import 'team_recruiting_widgets.dart';

typedef ClubFavoriteToggle = Future<void> Function(
  Club club,
  bool isFavorite,
);

class SimpleClubGrid extends StatelessWidget {
  final List<Club> clubs;
  final Set<String> favoriteIds;
  final ClubFavoriteToggle? onFavoriteToggle;

  const SimpleClubGrid({
    super.key,
    required this.clubs,
    required this.favoriteIds,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final club in clubs.take(4))
          SizedBox(
            width: 180,
            child: SimpleClubMiniTile(
              club: club,
              isFavorite: favoriteIds.contains(club.id),
              onFavoriteToggle: onFavoriteToggle,
            ),
          ),
      ],
    );
  }
}

class NearbyNewClubsSheet extends StatelessWidget {
  final List<Club> clubs;
  final Set<String> favoriteIds;
  final ClubFavoriteToggle? onFavoriteToggle;

  const NearbyNewClubsSheet({
    super.key,
    required this.clubs,
    required this.favoriteIds,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(Icons.near_me_rounded, color: cs.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내 주변 새 클럽',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '반경 5km · 최근 7일 안에 생성된 클럽',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (clubs.isEmpty)
                Expanded(
                  child: Center(
                    child: AppEmptyState(
                      icon: Icons.groups_2_rounded,
                      title: '새로 생긴 클럽이 없습니다',
                      description: '관심 조건을 바꾸거나 조금 뒤에 다시 확인해보세요.',
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: clubs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final club = clubs[index];
                      return NearbyNewClubCard(
                        club: club,
                        isFavorite: favoriteIds.contains(club.id),
                        onFavoriteToggle: onFavoriteToggle,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NearbyNewClubCard extends StatelessWidget {
  final Club club;
  final bool isFavorite;
  final ClubFavoriteToggle? onFavoriteToggle;

  const NearbyNewClubCard({
    super.key,
    required this.club,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final createdAt = club.createdAt;
    final daysAgo =
        createdAt == null ? null : DateTime.now().difference(createdAt).inDays;
    final createdLabel = daysAgo == null
        ? '최근 생성'
        : daysAgo == 0
            ? '오늘 생성'
            : '$daysAgo일 전 생성';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          SimpleClubAvatar(club: club, size: 64),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        'NEW',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      createdLabel,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  club.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  club.description ?? '새로 등록된 클럽입니다.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    MiniInfoChip(
                      icon: club.sport == 'futsal'
                          ? Icons.sports_soccer_rounded
                          : Icons.sports_tennis_rounded,
                      label: sportLabelFromString(club.sport),
                    ),
                    MiniInfoChip(
                      icon: Icons.place_rounded,
                      label: club.region ?? '지역 미정',
                    ),
                    MiniInfoChip(
                      icon: Icons.groups_rounded,
                      label: clubMemberCountLabel(club.memberCount),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
            onPressed: onFavoriteToggle == null
                ? null
                : () => onFavoriteToggle!(club, isFavorite),
            icon: Icon(
              isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
            ),
            color: isFavorite ? cs.primary : cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class SimpleClubMiniTile extends StatelessWidget {
  final Club club;
  final bool isFavorite;
  final ClubFavoriteToggle? onFavoriteToggle;

  const SimpleClubMiniTile({
    super.key,
    required this.club,
    required this.isFavorite,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        SimpleClubAvatar(club: club, size: 52),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'} · ${clubMemberCountLabel(club.memberCount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
          onPressed: onFavoriteToggle == null
              ? null
              : () => onFavoriteToggle!(club, isFavorite),
          icon: Icon(
            isFavorite
                ? Icons.bookmark_rounded
                : Icons.bookmark_outline_rounded,
          ),
          color: isFavorite ? cs.primary : cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class SimpleClubTile extends StatelessWidget {
  final Club? club;
  final bool isFavorite;
  final bool pending;
  final ClubFavoriteToggle? onFavoriteToggle;
  final VoidCallback? onOpen;

  const SimpleClubTile({
    super.key,
    required this.club,
    this.isFavorite = false,
    this.pending = false,
    this.onFavoriteToggle,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final item = club;

    if (item == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: cs.outlineVariant),
            bottom: BorderSide(color: cs.outlineVariant),
          ),
        ),
        child: Text(
          '관심 있는 클럽을 찾아 가입해보세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen ?? () => context.push('/clubs/${item.id}', extra: item),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SimpleClubAvatar(club: item, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleMedium,
                          ),
                        ),
                        if (pending) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              '승인 대기중',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.description ?? '새로운 클럽 일정을 확인해보세요.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text(
                          '${sportLabelFromString(item.sport)} / ${item.region ?? '지역 미정'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          clubMemberCountLabel(item.memberCount),
                          style: tt.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isFavorite ? '관심 해제' : '관심 클럽 저장',
                onPressed: onFavoriteToggle == null
                    ? null
                    : () => onFavoriteToggle!(item, isFavorite),
                icon: Icon(
                  isFavorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                ),
                color: isFavorite ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SimpleClubAvatar extends StatelessWidget {
  final Club club;
  final double size;

  const SimpleClubAvatar({
    super.key,
    required this.club,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _clubLogoSpec(club);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: _ClubAvatarImage(
        logoUrl: club.logoUrl,
        fallbackIcon: spec.icon,
        fallbackColor: spec.foreground,
        iconSize: size * 0.48,
      ),
    );
  }

  ClubLogoSpec _clubLogoSpec(Club club) {
    if (club.sport == 'tennis') {
      return const ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFEDF1FF),
        foreground: Color(0xFF3156D8),
      );
    }
    return const ClubLogoSpec(
      icon: Icons.sports_soccer_rounded,
      background: Color(0xFFEDF1FF),
      foreground: Color(0xFF3156D8),
    );
  }
}

class _ClubAvatarImage extends StatelessWidget {
  final String? logoUrl;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double iconSize;

  const _ClubAvatarImage({
    required this.logoUrl,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final url = logoUrl?.trim();
    final fallback = Icon(
      fallbackIcon,
      color: fallbackColor,
      size: iconSize,
    );

    if (url == null || url.isEmpty) return fallback;

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class ClubLogoSpec {
  final IconData icon;
  final Color background;
  final Color foreground;

  const ClubLogoSpec({
    required this.icon,
    required this.background,
    required this.foreground,
  });
}
