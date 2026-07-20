import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_skeleton_card.dart';
import '../widgets/app_toast.dart';
import '../widgets/clubs/club_tiles.dart';
import '../widgets/tournament_card.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: AllRoundE2EKeys.favoritesScreen,
      appBar: AppBar(
        title: const Text('관심 목록'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '대회'),
            Tab(text: '클럽'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _FavoriteTournamentsTab(),
          _FavoriteClubsTab(),
        ],
      ),
    );
  }
}

class _FavoriteTournamentsTab extends ConsumerWidget {
  const _FavoriteTournamentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.userDesignPreview) {
      return KeyedSubtree(
        key: AllRoundE2EKeys.favoritesReady,
        child: _TournamentList(tournaments: _previewFavoriteTournaments),
      );
    }

    final tournaments = ref.watch(myFavoriteTournamentsProvider);
    final favoriteIds = ref.watch(favoriteIdsProvider).valueOrNull;

    return tournaments.when(
      data: (items) {
        if (items.isEmpty) {
          return const KeyedSubtree(
            key: AllRoundE2EKeys.favoritesReady,
            child: AppEmptyState(
              icon: Icons.bookmark_border_rounded,
              title: '스크랩한 대회가 없습니다',
              description: '대회 목록에서 북마크를 누르면 이곳에 모입니다.',
            ),
          );
        }
        return KeyedSubtree(
          key: AllRoundE2EKeys.favoritesReady,
          child: _TournamentList(
            tournaments: items,
            favoriteIds: favoriteIds,
            onFavoriteToggle: (tournament) async {
              try {
                await ref
                    .read(apiProvider)
                    .toggleFavorite(tournament.id, false);
                ref.invalidate(favoriteIdsProvider);
                ref.invalidate(myFavoriteTournamentsProvider);
                ref.invalidate(myTournamentRecordsProvider);
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(
                    context,
                    '관심 해제에 실패했어요. 잠시 후 다시 시도해 주세요.',
                    kind: AppToastKind.error,
                  );
                }
              }
            },
          ),
        );
      },
      loading: () => const _FavoriteLoadingList(),
      error: (_, __) => AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: '관심 대회를 불러오지 못했습니다',
        description: '잠시 후 다시 시도해 주세요.',
        actionLabel: '다시 불러오기',
        onAction: () => ref.invalidate(myFavoriteTournamentsProvider),
      ),
    );
  }
}

class _TournamentList extends StatelessWidget {
  final List<Tournament> tournaments;
  final Set<String>? favoriteIds;
  final ValueChanged<Tournament>? onFavoriteToggle;

  const _TournamentList({
    required this.tournaments,
    this.favoriteIds,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      itemCount: tournaments.length,
      itemBuilder: (_, index) {
        final tournament = tournaments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TournamentCard(
            tournament: tournament,
            isFavorite: favoriteIds?.contains(tournament.id) ?? true,
            onTap: () => context.push('/tournaments/${tournament.id}'),
            onFavoriteToggle: onFavoriteToggle == null
                ? null
                : () => onFavoriteToggle!(tournament),
          ),
        );
      },
    );
  }
}

class _FavoriteClubsTab extends ConsumerWidget {
  const _FavoriteClubsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.userDesignPreview) {
      return _ClubList(clubs: _previewFavoriteClubs);
    }

    final clubs = ref.watch(myFavoriteClubsProvider);

    return clubs.when(
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.groups_outlined,
            title: '스크랩한 클럽이 없습니다',
            description: '클럽 찾기에서 북마크를 누르면 이곳에 모입니다.',
          );
        }
        return _ClubList(
          clubs: items,
          onFavoriteToggle: (club) async {
            await ref.read(apiProvider).toggleClubFavorite(club.id, false);
            ref.invalidate(clubFavoriteIdsProvider);
            ref.invalidate(myFavoriteClubsProvider);
          },
        );
      },
      loading: () => const _FavoriteLoadingList(),
      error: (_, __) => AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: '관심 클럽을 불러오지 못했습니다',
        description: '잠시 후 다시 시도해 주세요.',
        actionLabel: '다시 불러오기',
        onAction: () => ref.invalidate(myFavoriteClubsProvider),
      ),
    );
  }
}

class _ClubList extends StatelessWidget {
  final List<Club> clubs;
  final ValueChanged<Club>? onFavoriteToggle;

  const _ClubList({required this.clubs, this.onFavoriteToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      itemCount: clubs.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: cs.outlineVariant,
      ),
      itemBuilder: (_, index) {
        final club = clubs[index];
        return _FavoriteClubRow(
          club: club,
          onTap: () => context.push('/clubs/${club.id}', extra: club),
          onFavoriteToggle:
              onFavoriteToggle == null ? null : () => onFavoriteToggle!(club),
        );
      },
    );
  }
}

class _FavoriteClubRow extends StatelessWidget {
  final Club club;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  const _FavoriteClubRow({
    required this.club,
    required this.onTap,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
      if (club.memberCount > 0) '${club.memberCount}명',
    ].whereType<String>().join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.listRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                SimpleClubAvatar(club: club, size: 56),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        club.name,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (club.description != null &&
                          club.description!.isNotEmpty)
                        Text(
                          club.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: AppSizes.touchTarget,
                  height: AppSizes.touchTarget,
                  child: IconButton(
                    tooltip: '관심 해제',
                    onPressed: onFavoriteToggle,
                    icon: const Icon(Icons.bookmark_rounded),
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteLoadingList extends StatelessWidget {
  const _FavoriteLoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSkeletonCard(
      loading: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        itemCount: 4,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: cs.outlineVariant,
        ),
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 156,
                      height: 15,
                      color: cs.surfaceContainerHighest,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: 112,
                      height: 11,
                      color: cs.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _previewFavoriteTournaments = [
  Tournament(
    id: 'preview-futsal-sleague-2026',
    sport: 'futsal',
    title: '2026 생활체육 서울시민리그 풋살리그',
    organizer: '서울특별시풋살연맹',
    description: '서울시민리그 공식 풋살 페이지 기준 리그 일정입니다.',
    startDate: DateTime(2026, 6, 20),
    endDate: DateTime(2026, 10, 11),
    applicationDeadline: DateTime(2026, 6, 7),
    region: '서울',
    location: '서울시민리그 풋살 공식 경기장소',
    eligibleGrades: const [
      'intro',
      'beginner',
      'intermediate',
      'advanced',
      'elite'
    ],
    format: '서울시민리그 풋살 리그전',
    sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
    status: 'published',
    futsalEventCategory: 'sports_for_all',
  ),
];

final _previewFavoriteClubs = [
  Club(
    id: 'preview-club-futsal',
    sport: 'futsal',
    name: '서울 풋살 러너스',
    region: '서울',
    address: '서울 송파구',
    description: '주말 저녁 풋살 멤버를 모집하는 클럽',
    memberCount: 24,
  ),
  Club(
    id: 'preview-club-tennis',
    sport: 'tennis',
    name: '광주 테니스 크루',
    region: '광주',
    address: '광주 서구',
    description: '초중급 복식 위주로 함께 치는 클럽',
    memberCount: 38,
  ),
];
