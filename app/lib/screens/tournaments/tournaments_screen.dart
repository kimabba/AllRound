import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
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
  bool _usingPreviewData = false;
  String? _error;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiProvider);
    if (!kReleaseMode && AppConfig.apiBaseUrl.contains('127.0.0.1')) {
      setState(() {
        _results = _previewTournaments(ref.read(activeSportProvider));
        _usingPreviewData = true;
        _loading = false;
      });
      return;
    }

    List<Tournament> res;
    try {
      res = await api.searchTournaments(
        sport: ref.read(activeSportProvider),
        onlyMyGrade: _onlyMyGrade,
        query: _q,
        limit: 100,
      );
    } catch (e) {
      if (!kReleaseMode && mounted) {
        setState(() {
          _results = _previewTournaments(ref.read(activeSportProvider));
          _usingPreviewData = true;
          _error = null;
          _loading = false;
        });
        return;
      }
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
        _usingPreviewData = false;
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
    ref.listen(activeSportProvider, (_, __) => _search());
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
          if (_usingPreviewData) const _PreviewDataBanner(),
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

List<Tournament> _previewTournaments(String? sport) {
  final now = DateTime.now();
  if (sport == 'futsal') {
    return [
      Tournament(
        id: 'preview-futsal-sleague-2026',
        sport: 'futsal',
        title: '2026 생활체육 서울시민리그 풋살리그',
        organizer: '서울특별시풋살연맹',
        description:
            '서울시민리그 공식 풋살 페이지 기준 2차 접수는 2026년 5월 1일부터 6월 7일까지, 리그는 2026년 6월 20일부터 10월 11일까지 진행됩니다.',
        startDate: DateTime(2026, 6, 20),
        endDate: DateTime(2026, 10, 11),
        applicationDeadline: DateTime(2026, 6, 7),
        region: '서울',
        location: '서울시민리그 풋살 공식 경기장소',
        eligibleGrades: const ['beginner', 'intermediate', 'advanced'],
        prize: null,
        format: '서울시민리그 풋살 리그전',
        sourceUrl: 'https://www.sleague.or.kr/2026/futsal/',
        status: 'published',
      ),
      Tournament(
        id: 'preview-futsal-1',
        sport: 'futsal',
        title: '서울 풋살 위클리 컵',
        organizer: '매치업 풋살 커뮤니티',
        description: '주말 저녁에 열리는 5대5 풋살 모집전',
        startDate: now.add(const Duration(days: 9)),
        endDate: now.add(const Duration(days: 9)),
        applicationDeadline: now.add(const Duration(days: 4)),
        region: '수도권',
        location: '서울 송파 풋살파크',
        eligibleGrades: const ['beginner', 'intermediate'],
        entryFee: 80000,
        prize: '우승팀 구장 이용권',
        format: '5대5 조별리그',
        status: 'published',
      ),
      Tournament(
        id: 'preview-futsal-2',
        sport: 'futsal',
        title: '부산 야간 풋살 리그',
        organizer: '부산 풋살 연합',
        description: '퇴근 후 참여 가능한 지역 풋살 리그',
        startDate: now.add(const Duration(days: 18)),
        endDate: now.add(const Duration(days: 18)),
        applicationDeadline: now.add(const Duration(days: 11)),
        region: '부산·울산·경남',
        location: '부산 사직 풋살장',
        eligibleGrades: const ['advanced'],
        entryFee: 100000,
        prize: '우승 트로피',
        format: '토너먼트',
        status: 'published',
      ),
    ];
  }
  return [
    Tournament(
      id: 'preview-tennis-1',
      sport: 'tennis',
      title: '광주 오픈 테니스 챌린지',
      organizer: '광주테니스협회',
      description: '지역 동호인을 위한 복식 대회',
      startDate: now.add(const Duration(days: 12)),
      endDate: now.add(const Duration(days: 13)),
      applicationDeadline: now.add(const Duration(days: 5)),
      region: '광주',
      location: '염주실내테니스장',
      eligibleGrades: const ['under1y', 'y1to3'],
      entryFee: 40000,
      entryFeeUnit: 'per_person',
      prize: '우승 상품권',
      format: '복식 조별리그',
      status: 'published',
    ),
    Tournament(
      id: 'preview-tennis-2',
      sport: 'tennis',
      title: '수도권 동호인 랭킹전',
      organizer: 'KATA 수도권 지부',
      description: '등급별 자동 추천에 맞춘 랭킹전',
      startDate: now.add(const Duration(days: 21)),
      endDate: now.add(const Duration(days: 21)),
      applicationDeadline: now.add(const Duration(days: 14)),
      region: '수도권',
      location: '분당 테니스파크',
      eligibleGrades: const ['intermediate', 'advanced'],
      entryFee: 50000,
      entryFeeUnit: 'per_person',
      prize: '랭킹 포인트',
      format: '복식 토너먼트',
      status: 'published',
    ),
  ];
}

class _PreviewDataBanner extends StatelessWidget {
  const _PreviewDataBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: cs.tertiaryContainer.withValues(alpha: 0.7),
      child: Row(
        children: [
          Icon(Icons.visibility_rounded,
              size: 18, color: cs.onTertiaryContainer),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '백엔드 연결 전 디자인 미리보기 데이터입니다.',
              style: tt.labelMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w800,
              ),
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
                height: 150,
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
