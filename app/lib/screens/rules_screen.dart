import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models/rule_popularity.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/color_schemes.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../utils/grade_labels.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_skeleton_card.dart';
import '../widgets/notification_inbox_action.dart';
import '../widgets/tournament_section_bar.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key, this.initialSport, this.initialCategory});

  final String? initialSport;
  final String? initialCategory;

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  late String _selectedSport;
  late final TextEditingController _search;
  Map<String, List<RuleArticle>>? _tennisByCat;
  Map<String, List<RuleArticle>>? _futsalByCat;
  Map<String, List<RuleArticle>>? _activeByCat;
  RulePopularityHighlight? _tennisHighlight;
  RulePopularityHighlight? _futsalHighlight;
  RulePopularityHighlight? _activeHighlight;
  String? _activeSport;
  String? _error;
  String? _tennisError;
  String? _futsalError;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // 다른 화면(home_screen, sport_title, clubs_screen)과 같은 기본값 —
    // 주 종목이 아직 없는 사용자는 전부 풋살을 기본으로 본다.
    _selectedSport = ref.read(activeSportProvider) ?? 'futsal';
    _search = TextEditingController(text: widget.initialCategory ?? '');
    _query = _search.text.trim();
    _search.addListener(() {
      setState(() => _query = _search.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _tennisError = null;
      _futsalError = null;
    });

    final api = ref.read(apiProvider);
    // 명시적 딥링크(initialSport)일 때만 종목 하나짜리 읽기 화면으로 보낸다.
    // 여기서 activeSportProvider로 폴백하면 주 종목을 설정한 모든 로그인
    // 사용자가 항상 이 분기로 빠져 아래 레일(종목 전환)이 렌더링되지 않는다.
    final sport = widget.initialSport;
    _activeSport = sport;

    if (!kReleaseMode &&
        (AppConfig.userDesignPreview ||
            AppConfig.apiBaseUrl.contains('127.0.0.1'))) {
      setState(() {
        if (sport != null) {
          _activeByCat = _previewRulesFor(sport);
          _activeHighlight = _previewHighlightFor(sport);
        } else {
          _tennisByCat = _previewRulesFor('tennis');
          _futsalByCat = _previewRulesFor('futsal');
          _tennisHighlight = _previewHighlightFor('tennis');
          _futsalHighlight = _previewHighlightFor('futsal');
        }
        _loading = false;
      });
      return;
    }

    try {
      if (sport != null) {
        final rules = await api.listRules(sport);
        RulePopularityHighlight? highlight;
        try {
          highlight = await api.popularRuleHighlight24h(sport);
        } catch (_) {
          // 인기 집계가 실패해도 전체 룰북은 정상적으로 열려야 한다.
        }
        if (!mounted) return;
        setState(() {
          _activeByCat = _groupByCategory(rules);
          _activeHighlight = highlight;
          _loading = false;
        });
      } else {
        Future<_SportRulesLoadResult> loadSportRules(String value) async {
          try {
            final rules = await api.listRules(value);
            RulePopularityHighlight? highlight;
            try {
              highlight = await api.popularRuleHighlight24h(value);
            } catch (_) {
              // 인기 집계가 실패해도 해당 종목 규칙 목록은 그대로 표시한다.
            }
            return _SportRulesLoadResult(rules: rules, highlight: highlight);
          } catch (_) {
            return const _SportRulesLoadResult.failed();
          }
        }

        final results = await Future.wait([
          loadSportRules('tennis'),
          loadSportRules('futsal'),
        ]);
        final tennis = results[0];
        final futsal = results[1];
        if (!mounted) return;
        setState(() {
          _tennisByCat =
              tennis.rules == null ? null : _groupByCategory(tennis.rules!);
          _futsalByCat =
              futsal.rules == null ? null : _groupByCategory(futsal.rules!);
          _tennisHighlight = tennis.highlight;
          _futsalHighlight = futsal.highlight;
          _tennisError = tennis.failed ? _sportLoadError('tennis') : null;
          _futsalError = futsal.failed ? _sportLoadError('futsal') : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!kReleaseMode) {
        setState(() {
          if (sport != null) {
            _activeByCat = _previewRulesFor(sport);
            _activeHighlight = _previewHighlightFor(sport);
          } else {
            _tennisByCat = _previewRulesFor('tennis');
            _futsalByCat = _previewRulesFor('futsal');
            _tennisHighlight = _previewHighlightFor('tennis');
            _futsalHighlight = _previewHighlightFor('futsal');
          }
          _error = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = '룰북을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
        _loading = false;
      });
    }
  }

  Map<String, List<RuleArticle>> _groupByCategory(List<RuleArticle> list) {
    final out = <String, List<RuleArticle>>{};
    for (final article in list) {
      out.putIfAbsent(article.category, () => []).add(article);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialSport == null) {
      // 다른 화면(홈 타이틀 등)에서 종목을 바꾸면 레일 선택도 함께 따라간다 —
      // activeSportProvider가 앱 전체 종목 기준점이라는 기존 원칙과 동일.
      // 레일 자체도 이 기준점을 통해 선택하므로(아래 onSelected), 이 리스너는
      // 레일 탭 자신의 변경도 그대로 반영한다. 두 종목 데이터를 이미 함께
      // 불러와 둔 상태라 선택만 바뀔 땐 다시 불러올 필요가 없다(_load() 호출
      // 없음) — 예전엔 activeSportProvider가 단일종목 읽기 화면 분기까지
      // 좌우해서 재조회가 필요했지만, 그 분기가 딥링크 전용으로 바뀌며 더는
      // 아니다.
      ref.listen(activeSportProvider, (_, next) {
        if (next != null) setState(() => _selectedSport = next);
      });
    }

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        key: AllRoundE2EKeys.rulesScreen,
        appBar: AppBar(
          title: const Text('룰북'),
          actions: _rulesAppBarActions,
          bottom: _tournamentSectionBar(),
        ),
        body: const _RulesLoadingState(),
      );
    }

    if (_error != null) {
      return Scaffold(
        key: AllRoundE2EKeys.rulesScreen,
        appBar: AppBar(
          title: const Text('룰북'),
          actions: _rulesAppBarActions,
          bottom: _tournamentSectionBar(),
        ),
        body: AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: '룰북을 불러올 수 없어요',
          description: _error,
          actionLabel: '다시 시도',
          onAction: _load,
        ),
      );
    }

    if (_activeSport != null && _activeByCat != null) {
      return Scaffold(
        key: AllRoundE2EKeys.rulesScreen,
        appBar: AppBar(
          title: Text(_titleForSport(_activeSport!)),
          actions: _rulesAppBarActions,
          bottom: _tournamentSectionBar(),
        ),
        backgroundColor: cs.surface,
        body: KeyedSubtree(
          key: AllRoundE2EKeys.rulesReady,
          child: _RuleBookBody(
            grouped: _activeByCat,
            sport: _activeSport!,
            query: _query,
            searchController: _search,
            highlight: _activeHighlight,
          ),
        ),
      );
    }

    return Scaffold(
      key: AllRoundE2EKeys.rulesScreen,
      appBar: AppBar(
        title: const Text('룰북'),
        actions: _rulesAppBarActions,
        bottom: _tournamentSectionBar(),
      ),
      backgroundColor: cs.surface,
      body: KeyedSubtree(
        key: AllRoundE2EKeys.rulesReady,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 0),
              child: _SportRailToggle(
                selected: _selectedSport,
                // 로컬 상태만 바꾸면 홈·클럽 등 다른 화면은 여전히 예전
                // 종목을 본다 — activeSportProvider(sportOverrideProvider)를
                // 직접 갱신해 앱 전체 기준점을 따라가게 한다. _selectedSport
                // 자체는 위 ref.listen이 이 변경을 되돌려받아 갱신한다.
                onSelected: (sport) =>
                    ref.read(sportOverrideProvider.notifier).select(sport),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              // 종목을 바꿔도 각자 검색·아코디언 상태를 유지하도록 두 종목의
              // 본문을 계속 살려둔다(예전 TabBarView와 동일한 keep-alive 성격).
              child: IndexedStack(
                index: _selectedSport == 'tennis' ? 0 : 1,
                children: [
                  _RuleBookBody(
                    grouped: _tennisByCat,
                    sport: 'tennis',
                    query: _query,
                    searchController: _search,
                    highlight: _tennisHighlight,
                    error: _tennisError,
                    onRetry: _load,
                  ),
                  _RuleBookBody(
                    grouped: _futsalByCat,
                    sport: 'futsal',
                    query: _query,
                    searchController: _search,
                    highlight: _futsalHighlight,
                    error: _futsalError,
                    onRetry: _load,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TournamentSectionBar _tournamentSectionBar() {
    return TournamentSectionBar(
      selected: TournamentSection.rules,
      showRankings: ref.watch(activeSportProvider) == 'tennis',
    );
  }

  String _titleForSport(String sport) => '${sportLabelFromString(sport)} 룰북';
}

class _RuleBookBody extends StatefulWidget {
  const _RuleBookBody({
    required this.grouped,
    required this.sport,
    required this.query,
    required this.searchController,
    required this.highlight,
    this.error,
    this.onRetry,
  });

  final Map<String, List<RuleArticle>>? grouped;
  final String sport;
  final String query;
  final TextEditingController searchController;
  final RulePopularityHighlight? highlight;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<_RuleBookBody> createState() => _RuleBookBodyState();
}

class _RuleBookBodyState extends State<_RuleBookBody> {
  String? _expandedCategory;

  @override
  void initState() {
    super.initState();
    _expandedCategory = widget.grouped?.keys.firstOrNull;
  }

  @override
  void didUpdateWidget(covariant _RuleBookBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grouped != widget.grouped &&
        (widget.grouped?.containsKey(_expandedCategory) ?? false) == false) {
      _expandedCategory = widget.grouped?.keys.firstOrNull;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: '${sportLabelFromString(widget.sport)} 룰북을 불러올 수 없어요',
            description: widget.error,
            actionLabel: '다시 시도',
            onAction: widget.onRetry,
          ),
        ],
      );
    }

    final filtered = _filtered(widget.grouped, widget.query);

    if (widget.grouped == null || widget.grouped!.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          _RuleSearchCard(
            controller: widget.searchController,
            sport: widget.sport,
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: '등록된 룰북이 없습니다',
            description: '관리자가 룰북을 등록하면 이곳에 표시됩니다.',
          ),
        ],
      );
    }

    final hasQuery = widget.query.isNotEmpty;
    final showHighlight = !hasQuery && widget.highlight != null;
    final textScale =
        MediaQuery.textScalerOf(context).scale(AppSpacing.lg) / AppSpacing.lg;
    // 인기 카드 제목이 2줄(maxLines:2)까지 커질 수 있어, 200% 글자에서도
    // 안 잘리게 상한을 넉넉히 둔다(레일이 생겨 폭이 좁아진 만큼 더 잘 접혀서
    // 이 카드의 세로 길이가 늘어난다).
    final scaleExtra = ((textScale - 1) * (AppSpacing.huge * 2.5))
        .clamp(0.0, AppSpacing.huge * 3)
        .toDouble();
    const searchBarHeight = 44.0;
    final headerExtent = showHighlight
        ? AppSpacing.lg +
            AppSizes.control * 2 +
            AppSpacing.huge +
            AppSpacing.md +
            searchBarHeight +
            AppSpacing.md +
            scaleExtra
        : AppSpacing.lg + searchBarHeight + AppSpacing.md;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RuleCategoryRail(
          categories: hasQuery
              ? const []
              : widget.grouped!.keys.toList(growable: false),
          expandedCategory: _expandedCategory,
          onTap: (category) {
            setState(() {
              _expandedCategory =
                  _expandedCategory == category ? null : category;
            });
          },
        ),
        const SizedBox(width: 14),
        Expanded(child: _buildContent(context, hasQuery, filtered, headerExtent)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool hasQuery,
    Map<String, List<RuleArticle>> filtered,
    double headerExtent,
  ) {
    final showHighlight = !hasQuery && widget.highlight != null;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _RuleBookHeaderDelegate(
            extent: headerExtent,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  if (showHighlight) ...[
                    Expanded(
                      child: _DailyPopularRuleCard(
                        highlight: widget.highlight!,
                        article: _articleById(
                          widget.grouped!,
                          widget.highlight!.articleId,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  SizedBox(
                    height: 44,
                    child: _RuleSearchCard(
                      controller: widget.searchController,
                      sport: widget.sport,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            0,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          sliver: SliverList.list(
            children: [
              if (!hasQuery) ...[
                _RuleBookSummary(grouped: widget.grouped!),
                const SizedBox(height: AppSpacing.sm),
                _RuleCategoryAccordion(
                  grouped: widget.grouped!,
                  sport: widget.sport,
                  expandedCategory: _expandedCategory,
                  onToggle: (category) {
                    setState(() {
                      _expandedCategory =
                          _expandedCategory == category ? null : category;
                    });
                  },
                ),
              ] else
                _PopularRulesList(
                  // 사용자가 직접 검색한 결과는 원하는 룰을 놓치지 않도록 전체 표시한다.
                  articles: _allArticles(filtered),
                  sport: widget.sport,
                  title: '검색 결과',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, List<RuleArticle>> _filtered(
    Map<String, List<RuleArticle>>? source,
    String query,
  ) {
    if (source == null) return const {};
    if (query.isEmpty) return source;
    final lower = query.toLowerCase();
    final out = <String, List<RuleArticle>>{};
    for (final entry in source.entries) {
      final categoryMatches = entry.key.toLowerCase().contains(lower);
      final articles = entry.value.where((article) {
        return categoryMatches ||
            article.title.toLowerCase().contains(lower) ||
            article.body.toLowerCase().contains(lower);
      }).toList();
      if (articles.isNotEmpty) out[entry.key] = articles;
    }
    return out;
  }

  List<RuleArticle> _allArticles(Map<String, List<RuleArticle>> source) =>
      source.values.expand((items) => items).toList();

  RuleArticle? _articleById(
    Map<String, List<RuleArticle>> source,
    String articleId,
  ) {
    for (final article in source.values.expand((items) => items)) {
      if (article.id == articleId) return article;
    }
    return null;
  }
}

/// 상단 종목 탭을 대신하는 종목 전환 레일 항목(테니스/풋살). 종목별 본문이
/// 오류·빈 상태여도 항상 떠 있어야 해서 `_RuleBookBody` 밖(화면 레벨)에 둔다.
class _SportRailToggle extends StatelessWidget {
  const _SportRailToggle({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RuleRailItem(
            icon: Icons.sports_tennis_rounded,
            label: sportLabel(Sport.tennis),
            selected: selected == 'tennis',
            onTap: () => onSelected('tennis'),
          ),
          const SizedBox(height: AppSpacing.xs),
          _RuleRailItem(
            icon: Icons.sports_soccer_rounded,
            label: sportLabel(Sport.futsal),
            selected: selected == 'futsal',
            onTap: () => onSelected('futsal'),
          ),
        ],
      ),
    );
  }
}

/// 아코디언 카테고리를 대신 고를 수 있는 왼쪽 레일. 종목 전환 레일 바로 아래
/// 이어 붙어 하나의 세로 레일처럼 보이도록 같은 폭(72)·같은 항목 스타일을 쓴다.
class _RuleCategoryRail extends StatelessWidget {
  const _RuleCategoryRail({
    required this.categories,
    required this.expandedCategory,
    required this.onTap,
  });

  final List<String> categories;
  final String? expandedCategory;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final category in categories) ...[
            _RuleRailItem(
              icon: _iconForCategory(category),
              label: category,
              selected: expandedCategory == category,
              onTap: () => onTap(category),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _RuleRailItem extends StatelessWidget {
  const _RuleRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;
    const radius = BorderRadius.only(
      topRight: Radius.circular(AppRadius.md),
      bottomRight: Radius.circular(AppRadius.md),
    );

    // TabBar가 자동으로 주던 "선택됨" 상태를 스크린리더가 다시 읽어주도록
    // 직접 표시한다 — 안 그러면 지금 어느 종목/카테고리를 보고 있는지
    // 안내가 사라진다.
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? cs.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: color,
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

class _RuleBookHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _RuleBookHeaderDelegate({
    required this.extent,
    required this.backgroundColor,
    required this.child,
  });

  final double extent;
  final Color backgroundColor;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(covariant _RuleBookHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent ||
        backgroundColor != oldDelegate.backgroundColor ||
        child != oldDelegate.child;
  }
}

class _SportRulesLoadResult {
  const _SportRulesLoadResult({required this.rules, this.highlight})
      : failed = false;

  const _SportRulesLoadResult.failed()
      : rules = null,
        highlight = null,
        failed = true;

  final List<RuleArticle>? rules;
  final RulePopularityHighlight? highlight;
  final bool failed;
}

String _sportLoadError(String sport) =>
    '${sportLabelFromString(sport)} 규칙만 불러오지 못했습니다. '
    '다른 종목 규칙은 계속 볼 수 있습니다.';

/// 룰북 화면의 앱바 액션. 화면이 로딩·오류·단일종목·탭 4갈래로 갈라지므로
/// 한 곳에만 넣으면 분기에 따라 마이 진입점이 사라진다(실제로 그랬다).
const _rulesAppBarActions = <Widget>[
  NotificationInboxAction(),
  ProfileAction(),
  SizedBox(width: 4),
];

class _RulesLoadingState extends StatelessWidget {
  const _RulesLoadingState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSkeletonCard(
      loading: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Container(
            height: AppSizes.control,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (var index = 0; index < 5; index++) ...[
            Container(
              height: AppSizes.listRow,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cs.outlineVariant)),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: index.isEven ? 0.72 : 0.56,
                child: Container(height: 14, color: cs.surfaceContainerHighest),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Map<String, List<RuleArticle>> _previewRulesFor(String sport) {
  final data = sport == 'futsal' ? _previewFutsalRules : _previewTennisRules;
  return {
    for (final entry in data.entries)
      entry.key: [
        for (var i = 0; i < entry.value.length; i++)
          RuleArticle(
            id: 'preview-$sport-${entry.key}-$i',
            sport: sport,
            category: entry.key,
            title: entry.value[i].$1,
            body: entry.value[i].$2,
            orderIdx: i,
            published: true,
          ),
      ],
  };
}

RulePopularityHighlight _previewHighlightFor(String sport) {
  final isFutsal = sport == 'futsal';
  return RulePopularityHighlight(
    articleId: isFutsal ? 'preview-futsal-경기 진행-0' : 'preview-tennis-경기 진행-0',
    sport: sport,
    category: '경기 진행',
    title: isFutsal ? '풋살 경기 시간' : '타이브레이크는 언제 하나요?',
    articleClickCount: isFutsal ? 18 : 24,
    categoryClickCount: isFutsal ? 31 : 42,
    windowStartedAt: DateTime.now().subtract(const Duration(hours: 24)),
  );
}

const _previewTennisRules = <String, List<(String, String)>>{
  '경기 진행': [
    ('타이브레이크는 언제 하나요?', '세트 스코어가 6-6이 되면 보통 타이브레이크로 세트 승자를 정합니다.'),
    ('듀스와 어드밴티지', '40-40 이후에는 연속 두 포인트를 먼저 따야 게임을 가져갑니다.'),
  ],
  '서브': [
    ('서브 폴트와 더블 폴트 차이', '첫 서브 실패는 폴트, 두 번째 서브까지 실패하면 더블 폴트로 상대 포인트입니다.'),
    ('렛 서브 처리', '서브가 네트를 맞고 서비스 박스에 들어가면 렛으로 다시 서브합니다.'),
  ],
  '발리': [
    ('네트 근처 발리 기본', '공이 바운드되기 전에 처리하는 샷이며, 네트를 건드리면 실점이 될 수 있습니다.'),
    ('오버넷 판정', '상대 코트 위에서 공을 치는 행위는 상황에 따라 반칙으로 판단될 수 있습니다.'),
  ],
  '복식/라인': [
    ('복식 코트 라인', '복식은 양쪽 앨리까지 포함한 넓은 코트를 사용합니다.'),
    ('라인 판정', '공이 라인에 조금이라도 닿으면 인으로 봅니다.'),
  ],
};

const _previewFutsalRules = <String, List<(String, String)>>{
  '경기 진행': [
    ('풋살 경기 시간', '전·후반 20분이 기본이며, 대회 규정에 따라 러닝타임 또는 스톱타임을 적용합니다.'),
    ('선수 수와 교체', '골키퍼 포함 5명이 경기하고, 지정된 교체 구역을 지키면 경기 중 반복 교체가 가능합니다.'),
  ],
  '골키퍼': [
    ('골키퍼 4초 제한', '골키퍼는 자기 진영에서 볼을 4초 넘게 컨트롤할 수 없습니다.'),
    ('백패스 제한', '골키퍼가 플레이한 볼은 상대 선수 터치 없이 다시 골키퍼에게 돌아갈 수 없습니다.'),
  ],
  '파울': [
    ('누적 파울', '한 하프에서 직접 프리킥성 파울이 누적되면 이후 상대팀에게 더 위험한 프리킥 기회가 주어집니다.'),
    ('위험한 접촉', '무리한 슬라이딩과 위험한 접촉은 파울 또는 경고가 될 수 있습니다.'),
  ],
  '킥인/재개': [
    ('킥인 재개', '볼이 터치라인을 넘으면 손으로 던지지 않고 킥인으로 경기를 재개합니다.'),
    ('코너킥과 골 클리어런스', '골라인을 넘은 볼은 마지막 터치한 팀에 따라 코너킥 또는 골 클리어런스로 재개합니다.'),
  ],
  '장비/경기장': [
    ('풋살공과 피치', '풋살은 반발력이 낮은 4호공과 전용 피치를 사용합니다.'),
    ('기본 장비', '유니폼, 스타킹, 신발, 정강이 보호대를 착용하고 골키퍼는 구분되는 색상을 입습니다.'),
  ],
};

class _RuleSearchCard extends StatelessWidget {
  const _RuleSearchCard({required this.controller, required this.sport});

  final TextEditingController controller;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _accentFor(context, sport);

    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        hintText: '룰 검색하기...',
        hintStyle: const TextStyle(fontSize: 15),
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        suffixIcon: Icon(
          sport == 'tennis'
              ? Icons.sports_tennis_rounded
              : Icons.sports_soccer_rounded,
          color: accent,
        ),
      ),
    );
  }
}

class _DailyPopularRuleCard extends ConsumerWidget {
  const _DailyPopularRuleCard({required this.highlight, required this.article});

  final RulePopularityHighlight highlight;
  final RuleArticle? article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.hero,
      child: InkWell(
        onTap: article == null
            ? null
            : () {
                if (!AppConfig.userDesignPreview) {
                  unawaited(_recordRuleClick(ref, article!.id));
                }
                _showArticle(context, article!);
              },
        borderRadius: AppRadius.hero,
        child: Ink(
          decoration: const BoxDecoration(
            borderRadius: AppRadius.hero,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppPalette.accentPressed, AppPalette.accent],
            ),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.hero,
            child: Stack(
              children: [
                Positioned(
                  right: -AppSpacing.xxxl,
                  bottom: -AppSpacing.huge,
                  child: Container(
                    width: AppSizes.touchTarget * 3,
                    height: AppSizes.touchTarget * 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppPalette.photoForeground.withValues(
                          alpha: 0.12,
                        ),
                        width: AppSpacing.xxl,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '오늘 가장 많이 받은 클릭',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelMedium?.copyWith(
                                color: AppPalette.photoForeground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '최근 24시간',
                            style: tt.labelSmall?.copyWith(
                              color: AppPalette.photoForeground,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _displayRuleTitle(highlight.title),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge?.copyWith(
                          color: AppPalette.photoForeground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${highlight.category} · '
                              '${highlight.articleClickCount}회 클릭',
                              style: tt.bodySmall?.copyWith(
                                color: AppPalette.photoForeground,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: AppPalette.photoForeground,
                          ),
                        ],
                      ),
                    ],
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

class _RuleBookSummary extends StatelessWidget {
  const _RuleBookSummary({required this.grouped});

  final Map<String, List<RuleArticle>> grouped;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final articleCount = grouped.values.fold<int>(
      0,
      (total, articles) => total + articles.length,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            '전체 룰북',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        // 레일이 생기면서 이 줄이 쓸 수 있는 폭이 좁아졌다 — 200% 글자에서
        // "N개 분류 · N개 규칙"이 안 들어갈 수 있어 줄여 쓰게 한다.
        Flexible(
          child: Text(
            '${grouped.length}개 분류 · $articleCount개 규칙',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _RuleCategoryAccordion extends StatelessWidget {
  const _RuleCategoryAccordion({
    required this.grouped,
    required this.sport,
    required this.expandedCategory,
    required this.onToggle,
  });

  final Map<String, List<RuleArticle>> grouped;
  final String sport;
  final String? expandedCategory;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final entries = grouped.entries.toList(growable: false);
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++)
          _RuleCategorySection(
            index: index,
            title: entries[index].key,
            articles: entries[index].value,
            sport: sport,
            expanded: expandedCategory == entries[index].key,
            onToggle: () => onToggle(entries[index].key),
          ),
      ],
    );
  }
}

class _RuleCategorySection extends StatelessWidget {
  const _RuleCategorySection({
    required this.index,
    required this.title,
    required this.articles,
    required this.sport,
    required this.expanded,
    required this.onToggle,
  });

  final int index;
  final String title;
  final List<RuleArticle> articles;
  final String sport;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.listRow + AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: AppSizes.touchTarget,
                      height: AppSizes.touchTarget,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text(
                              (index + 1).toString().padLeft(2, '0'),
                              style: tt.labelMedium?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _descriptionForCategory(title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${articles.length}',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDuration.medium1,
            curve: AppCurves.standard,
            alignment: Alignment.topCenter,
            child: expanded
                ? _ExpandedRuleCategory(
                    title: title,
                    articles: articles,
                    sport: sport,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ExpandedRuleCategory extends StatelessWidget {
  const _ExpandedRuleCategory({
    required this.title,
    required this.articles,
    required this.sport,
  });

  final String title;
  final List<RuleArticle> articles;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final visible = articles.take(4).toList(growable: false);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.touchTarget + AppSpacing.sm,
          AppSpacing.sm,
          0,
          AppSpacing.sm,
        ),
        child: Column(
          children: [
            for (var i = 0; i < visible.length; i++)
              _AccordionRuleRow(article: visible[i], index: i),
            _OpenCategoryRow(
              count: articles.length,
              onTap: () => _showCategorySheet(context, title, articles, sport),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccordionRuleRow extends ConsumerWidget {
  const _AccordionRuleRow({required this.article, required this.index});

  final RuleArticle article;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!AppConfig.userDesignPreview) {
            unawaited(_recordRuleClick(ref, article.id));
          }
          _showArticle(context, article);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _displayRuleTitle(article.title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenCategoryRow extends StatelessWidget {
  const _OpenCategoryRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 20, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$count개 규칙 모두 보기',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showCategorySheet(
  BuildContext context,
  String title,
  List<RuleArticle> articles,
  String sport,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.68,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) => _CategorySheet(
        title: title,
        articles: articles,
        sport: sport,
        scrollController: scroll,
      ),
    ),
  );
}

class _PopularRulesList extends StatelessWidget {
  const _PopularRulesList({
    required this.articles,
    required this.sport,
    this.title = '자주 찾는 룰',
  });

  final List<RuleArticle> articles;
  final String sport;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    if (articles.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: '검색 결과가 없습니다',
        description: '다른 검색어를 입력해 보세요.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < articles.length; i++) ...[
          _ArticleRow(article: articles[i], index: i),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _ArticleRow extends ConsumerWidget {
  const _ArticleRow({required this.article, this.index, this.onOpen});

  final RuleArticle article;
  final int? index;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!AppConfig.userDesignPreview) {
            unawaited(_recordRuleClick(ref, article.id));
          }
          if (onOpen != null) {
            onOpen!();
          } else {
            _showArticle(context, article);
          }
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              if (index != null) ...[
                SizedBox(
                  width: 20,
                  child: Text(
                    '${index! + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  _displayRuleTitle(article.title),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _recordRuleClick(WidgetRef ref, String articleId) async {
  try {
    await ref.read(apiProvider).recordRuleArticleClick(articleId);
  } catch (_) {
    // 클릭 집계 실패가 룰 본문 열람을 막아서는 안 된다.
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({
    required this.title,
    required this.articles,
    required this.sport,
    required this.scrollController,
  });

  final String title;
  final List<RuleArticle> articles;
  final String sport;
  final ScrollController scrollController;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  RuleArticle? _selectedArticle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = _accentFor(context, widget.sport);
    final selectedArticle = _selectedArticle;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: AppRadius.pill,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (selectedArticle != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedArticle = null),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text('${widget.title} 목록'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MarkdownBody(
            data:
                '# ${_displayRuleTitle(selectedArticle.title)}\n\n${selectedArticle.body}',
          ),
        ] else ...[
          Row(
            children: [
              Icon(_iconForCategory(widget.title), color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.title,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < widget.articles.length; i++) ...[
            _ArticleRow(
              article: widget.articles[i],
              index: i,
              onOpen: () =>
                  setState(() => _selectedArticle = widget.articles[i]),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

void _showArticle(BuildContext context, RuleArticle article) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (_, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        child: Markdown(
          controller: scroll,
          data: '# ${_displayRuleTitle(article.title)}\n\n${article.body}',
        ),
      ),
    ),
  );
}

IconData _iconForCategory(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('점수') || lower.contains('score')) {
    return Icons.scoreboard_rounded;
  }
  if (lower.contains('서브') || lower.contains('serve')) {
    return Icons.sports_tennis_rounded;
  }
  if (lower.contains('발리') || lower.contains('volley')) {
    return Icons.flash_on_rounded;
  }
  if (lower.contains('라인') || lower.contains('line')) {
    return Icons.straighten_rounded;
  }
  if (lower.contains('복식') || lower.contains('double')) {
    return Icons.groups_2_rounded;
  }
  if (lower.contains('시간') || lower.contains('time')) {
    return Icons.timer_outlined;
  }
  if (lower.contains('골키퍼')) {
    return Icons.sports_handball_rounded;
  }
  if (lower.contains('킥인') || lower.contains('재개') || lower.contains('코너')) {
    return Icons.redo_rounded;
  }
  if (lower.contains('장비') || lower.contains('경기장') || lower.contains('피치')) {
    return Icons.sports_soccer_rounded;
  }
  if (lower.contains('연맹')) {
    return Icons.account_balance_rounded;
  }
  if (lower.contains('포지션') || lower.contains('전술')) {
    return Icons.route_rounded;
  }
  if (lower.contains('부상') || lower.contains('컨디션')) {
    return Icons.health_and_safety_rounded;
  }
  if (lower.contains('교체') || lower.contains('substitution')) {
    return Icons.swap_horiz_rounded;
  }
  if (lower.contains('경기') || lower.contains('game') || lower.contains('진행')) {
    return Icons.sports_score_rounded;
  }
  if (lower.contains('판정') || lower.contains('파울') || lower.contains('규칙')) {
    return Icons.balance_rounded;
  }
  if (lower.contains('매너') || lower.contains('에티켓')) {
    return Icons.handshake_rounded;
  }
  if (lower.contains('대회') || lower.contains('토너먼트')) {
    return Icons.emoji_events_rounded;
  }
  return Icons.menu_book_rounded;
}

String _descriptionForCategory(String category) {
  final lower = category.toLowerCase();
  if (lower.contains('점수') || lower.contains('score')) {
    return '포인트 · 게임 · 세트';
  }
  if (lower.contains('서브') || lower.contains('serve')) {
    return '폴트 · 렛 · 순서';
  }
  if (lower.contains('발리') || lower.contains('volley')) {
    return '네트 플레이 · 접촉';
  }
  if (lower.contains('라인') || lower.contains('line')) {
    return '인/아웃 · 코트 범위';
  }
  if (lower.contains('복식') || lower.contains('double')) {
    return '파트너 · 위치 · 라인';
  }
  if (lower.contains('시간') || lower.contains('time')) {
    return '제한 시간 · 진행 속도';
  }
  if (lower.contains('골키퍼')) {
    return '4초 제한 · 백패스';
  }
  if (lower.contains('킥인') || lower.contains('재개') || lower.contains('코너')) {
    return '킥인 · 코너킥 · 재개';
  }
  if (lower.contains('장비') || lower.contains('경기장') || lower.contains('피치')) {
    return '경기장 규격 · 골대 · 장비';
  }
  if (lower.contains('연맹')) {
    return '공식 기관 · 규칙서';
  }
  if (lower.contains('포지션') || lower.contains('전술')) {
    return '골레이로 · 픽소 · 아라 · 피보';
  }
  if (lower.contains('부상') || lower.contains('컨디션')) {
    return '부상 예방 · 회복';
  }
  if (lower.contains('교체') || lower.contains('substitution')) {
    return '선수 교체 · 절차';
  }
  if (lower.contains('경기') || lower.contains('game') || lower.contains('진행')) {
    return '시간 · 득점 · 흐름';
  }
  if (lower.contains('판정') || lower.contains('파울') || lower.contains('규칙')) {
    return '킥인 · 파울 · 판정';
  }
  if (lower.contains('매너') || lower.contains('에티켓')) {
    return '경기장 매너';
  }
  if (lower.contains('대회') || lower.contains('토너먼트')) {
    return '토너먼트 규정';
  }
  return '핵심 규칙 모음';
}

Color _accentFor(BuildContext context, String sport) {
  final cs = Theme.of(context).colorScheme;
  return sport == 'tennis' ? cs.tertiary : cs.secondary;
}

String _displayRuleTitle(String title) {
  return title
      .replaceFirst(RegExp(r'^\d+\.\s*'), '')
      .replaceFirst(RegExp(r'^제\d+조\s*[–-]\s*'), '')
      .replaceFirst(RegExp(r'^규칙\s*\d+(?:[·~]\d+)?\s*[–-]\s*'), '');
}
