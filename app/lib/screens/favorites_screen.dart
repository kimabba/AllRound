import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/matchup_logo.dart';
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
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '관심'),
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
      return _TournamentList(tournaments: _previewFavoriteTournaments);
    }

    final tournaments = ref.watch(myFavoriteTournamentsProvider);
    final favoriteIds = ref.watch(favoriteIdsProvider).valueOrNull;

    return tournaments.when(
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.bookmark_border_rounded,
            title: '스크랩한 대회가 없습니다',
            description: '대회 목록에서 북마크를 누르면 이곳에 모입니다.',
          );
        }
        return _TournamentList(
          tournaments: items,
          favoriteIds: favoriteIds,
          onFavoriteToggle: (tournament) async {
            await ref.read(apiProvider).toggleFavorite(tournament.id, false);
            ref.invalidate(favoriteIdsProvider);
            ref.invalidate(myFavoriteTournamentsProvider);
            ref.invalidate(myTournamentRecordsProvider);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: clubs.length,
      itemBuilder: (_, index) {
        final club = clubs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _FavoriteClubCard(
            club: club,
            onTap: () => context.push('/clubs/${club.id}', extra: club),
            onFavoriteToggle:
                onFavoriteToggle == null ? null : () => onFavoriteToggle!(club),
          ),
        );
      },
    );
  }
}

class _FavoriteClubCard extends StatelessWidget {
  final Club club;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  const _FavoriteClubCard({
    required this.club,
    required this.onTap,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isTennis = club.sport == 'tennis';
    final accent = isTennis ? cs.tertiary : cs.secondary;
    final meta = [
      sportLabelFromString(club.sport),
      if (club.region != null) club.region,
      if (club.memberCount > 0) '${club.memberCount}명',
    ].whereType<String>().join(' · ');

    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isTennis
                  ? Icons.sports_tennis_rounded
                  : Icons.sports_soccer_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  club.name,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (club.description != null && club.description!.isNotEmpty)
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
          IconButton(
            tooltip: '관심 해제',
            onPressed: onFavoriteToggle,
            icon: const Icon(Icons.bookmark_rounded),
            color: accent,
          ),
        ],
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
    eligibleGrades: const ['beginner', 'intermediate', 'advanced'],
    format: '서울시민리그 풋살 리그전',
    sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
    status: 'published',
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
