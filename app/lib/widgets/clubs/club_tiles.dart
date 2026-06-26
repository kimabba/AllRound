import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../theme/tokens.dart';
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
                      color: const Color(0xFFEAF7F1),
                      borderRadius: BorderRadius.circular(16),
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
        borderRadius: BorderRadius.circular(20),
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
                        color: const Color(0xFFE6F7C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'NEW',
                        style: tt.labelSmall?.copyWith(
                          color: const Color(0xFF4F8F00),
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
                      label: '멤버 ${club.memberCount}',
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
                '${sportLabelFromString(club.sport)} · ${club.region ?? '지역 미정'}',
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
  final ClubFavoriteToggle? onFavoriteToggle;

  const SimpleClubTile({
    super.key,
    required this.club,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final item = club;

    if (item == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          '관심 있는 클럽을 찾아 가입해보세요.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return InkWell(
      onTap: () => context.push('/clubs/${item.id}', extra: item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SimpleClubAvatar(club: item, size: 72),
                if (item.createdAt != null &&
                    DateTime.now().difference(item.createdAt!).inDays <= 7)
                  Positioned(
                    left: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF3B4F),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        'N',
                        style: tt.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.description ?? '새로운 클럽 일정을 확인해보세요.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sportLabelFromString(item.sport)} · ${item.region ?? '지역 미정'} · 멤버 ${item.memberCount}',
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
      decoration: BoxDecoration(
        color: spec.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(
        spec.icon,
        color: spec.foreground,
        size: size * 0.48,
      ),
    );
  }

  ClubLogoSpec _clubLogoSpec(Club club) {
    final name = club.name;
    if (name.contains('리얼')) {
      return const ClubLogoSpec(
        icon: Icons.shield_rounded,
        background: Color(0xFFE8F2FF),
        foreground: Color(0xFF2563EB),
      );
    }
    if (name.contains('올라운드')) {
      return const ClubLogoSpec(
        icon: Icons.all_inclusive_rounded,
        background: Color(0xFFEAF7F1),
        foreground: Color(0xFF059669),
      );
    }
    if (name.contains('위너스')) {
      return const ClubLogoSpec(
        icon: Icons.emoji_events_rounded,
        background: Color(0xFFFFF4D6),
        foreground: Color(0xFFF59E0B),
      );
    }
    if (name.contains('랠리')) {
      return const ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    if (name.contains('첨단')) {
      return const ClubLogoSpec(
        icon: Icons.bolt_rounded,
        background: Color(0xFFEDE9FE),
        foreground: Color(0xFF7C3AED),
      );
    }
    if (name.contains('주말')) {
      return const ClubLogoSpec(
        icon: Icons.wb_sunny_rounded,
        background: Color(0xFFFFF7ED),
        foreground: Color(0xFFEA580C),
      );
    }
    if (club.sport == 'tennis') {
      return const ClubLogoSpec(
        icon: Icons.sports_tennis_rounded,
        background: Color(0xFFFFF0D8),
        foreground: Color(0xFFFF7A1A),
      );
    }
    return const ClubLogoSpec(
      icon: Icons.sports_soccer_rounded,
      background: Color(0xFFE8F6D6),
      foreground: Color(0xFF7DCD18),
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
