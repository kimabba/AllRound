import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/matchup_logo.dart';
import '../../widgets/tournament_card.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  bool _onlyMyGrade = false;
  String _q = '';
  List<Tournament>? _results;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiProvider);
    List<Tournament> res;
    try {
      res = await api.searchTournaments(
        sport: ref.read(activeSportProvider),
        onlyMyGrade: _onlyMyGrade,
        query: _q,
        limit: 100,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _results = const [];
          _error = _formatSearchError(e);
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _results = res;
        _loading = false;
      });
    }
  }

  String _formatSearchError(Object error) {
    final text = error.toString();
    if (text.contains('503') || text.contains('BOOT_ERROR')) {
      return '대회 검색 서버가 아직 준비되지 않았습니다. 로컬 Supabase Edge Function 상태를 확인한 뒤 다시 시도해 주세요.';
    }
    if (text.contains('401') || text.contains('Authorization')) {
      return '로그인 세션을 확인할 수 없습니다. 다시 로그인한 뒤 시도해 주세요.';
    }
    return '대회 목록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(favoriteIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '대회 · 모집'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '대회 제보',
            onPressed: () => context.push('/tournaments/submit'),
          ),
        ],
      ),
      body: Column(
        children: [
          const _MyGradeSection(),
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '대회명·주최·설명 검색',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  onChanged: (v) => _q = v,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterPill(
                        label: '전체',
                        selected: !_onlyMyGrade,
                        onTap: () {
                          if (_onlyMyGrade) {
                            setState(() => _onlyMyGrade = false);
                            _search();
                          }
                        },
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FilterPill(
                        label: '이번주',
                        selected: false,
                        onTap: _search,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FilterPill(
                        label: '내 등급',
                        selected: _onlyMyGrade,
                        onTap: () {
                          setState(() => _onlyMyGrade = !_onlyMyGrade);
                          _search();
                        },
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FilterPill(label: '지역', selected: false, onTap: _search),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filledTonal(
                        onPressed: _search,
                        icon: const Icon(Icons.search_rounded),
                        tooltip: '검색',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading) LinearProgressIndicator(color: cs.primary),
          Expanded(
            child: _error != null
                ? _TournamentErrorState(message: _error!, onRetry: _search)
                : _results == null
                    ? const SizedBox.shrink()
                    : _results!.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.search_off_rounded,
                            title: '검색 결과 없음',
                            description: '다른 검색어나 필터로 시도해 보세요.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.lg,
                            ),
                            itemCount: _results!.length,
                            itemBuilder: (_, i) {
                              final tournament = _results![i];
                              final favs =
                                  favorites.valueOrNull ?? const <String>{};
                              return TournamentCard(
                                tournament: tournament,
                                isFavorite: favs.contains(tournament.id),
                                onTap: () => context
                                    .push('/tournaments/${tournament.id}'),
                                onFavoriteToggle: () async {
                                  await ref.read(apiProvider).toggleFavorite(
                                        tournament.id,
                                        !favs.contains(tournament.id),
                                      );
                                  ref.invalidate(favoriteIdsProvider);
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _TournamentErrorState extends StatelessWidget {
  const _TournamentErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              '대회 목록을 불러올 수 없어요',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected ? cs.primary : cs.surface,
      borderRadius: AppRadius.pill,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: tt.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyGradeSection extends ConsumerWidget {
  const _MyGradeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(homeTournamentsProvider);
    final favorites = ref.watch(favoriteIdsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '내 등급 추천 대회',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '맞춤 추천',
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          tournaments.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              final favs = favorites.valueOrNull ?? const <String>{};
              return SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final tournament = list[i];
                    return SizedBox(
                      width: 260,
                      child: TournamentCard(
                        tournament: tournament,
                        compact: true,
                        isFavorite: favs.contains(tournament.id),
                        onTap: () =>
                            context.push('/tournaments/${tournament.id}'),
                        onFavoriteToggle: () async {
                          final api = ref.read(apiProvider);
                          await api.toggleFavorite(
                            tournament.id,
                            !favs.contains(tournament.id),
                          );
                          ref.invalidate(favoriteIdsProvider);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Divider(color: cs.outlineVariant, height: 1),
        ],
      ),
    );
  }
}
