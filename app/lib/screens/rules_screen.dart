import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models/tournament.dart';
import '../state/providers.dart';
import '../testing/e2e_keys.dart';
import '../theme/tokens.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_skeleton_card.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _search = TextEditingController();
  Map<String, List<RuleArticle>>? _tennisByCat;
  Map<String, List<RuleArticle>>? _futsalByCat;
  Map<String, List<RuleArticle>>? _activeByCat;
  String? _activeSport;
  String? _error;
  bool _loading = true;
  bool _usingPreviewData = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _search.addListener(() {
      setState(() => _query = _search.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final api = ref.read(apiProvider);
    final sport = ref.read(activeSportProvider);
    _activeSport = sport;

    if (!kReleaseMode &&
        (AppConfig.userDesignPreview ||
            AppConfig.apiBaseUrl.contains('127.0.0.1'))) {
      setState(() {
        if (sport != null) {
          _activeByCat = _previewRulesFor(sport);
        } else {
          _tennisByCat = _previewRulesFor('tennis');
          _futsalByCat = _previewRulesFor('futsal');
        }
        _usingPreviewData = true;
        _loading = false;
      });
      return;
    }

    try {
      if (sport != null) {
        final rules = await api.listRules(sport);
        if (!mounted) return;
        setState(() {
          _activeByCat = _groupByCategory(rules);
          _usingPreviewData = false;
          _loading = false;
        });
      } else {
        final tennis = await api.listRules('tennis');
        final futsal = await api.listRules('futsal');
        if (!mounted) return;
        setState(() {
          _tennisByCat = _groupByCategory(tennis);
          _futsalByCat = _groupByCategory(futsal);
          _usingPreviewData = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!kReleaseMode) {
        setState(() {
          if (sport != null) {
            _activeByCat = _previewRulesFor(sport);
          } else {
            _tennisByCat = _previewRulesFor('tennis');
            _futsalByCat = _previewRulesFor('futsal');
          }
          _usingPreviewData = true;
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
      if (_shouldHideRuleCategory(article.sport, article.category)) continue;
      out.putIfAbsent(article.category, () => []).add(article);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) => _load());

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        key: AllRoundE2EKeys.rulesScreen,
        appBar: AppBar(title: const Text('룰북')),
        body: const _RulesLoadingState(),
      );
    }

    if (_error != null) {
      return Scaffold(
        key: AllRoundE2EKeys.rulesScreen,
        appBar: AppBar(title: const Text('룰북')),
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
        ),
        backgroundColor: cs.surface,
        body: KeyedSubtree(
          key: AllRoundE2EKeys.rulesReady,
          child: _RuleBookBody(
            grouped: _activeByCat,
            sport: _activeSport!,
            query: _query,
            searchController: _search,
            usingPreviewData: _usingPreviewData,
          ),
        ),
      );
    }

    return Scaffold(
      key: AllRoundE2EKeys.rulesScreen,
      appBar: AppBar(
        title: const Text('룰북'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.sports_tennis_rounded), text: '테니스'),
            Tab(icon: Icon(Icons.sports_soccer_rounded), text: '풋살'),
          ],
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
        ),
      ),
      backgroundColor: cs.surface,
      body: KeyedSubtree(
        key: AllRoundE2EKeys.rulesReady,
        child: TabBarView(
          controller: _tab,
          children: [
            _RuleBookBody(
              grouped: _tennisByCat,
              sport: 'tennis',
              query: _query,
              searchController: _search,
              usingPreviewData: _usingPreviewData,
            ),
            _RuleBookBody(
              grouped: _futsalByCat,
              sport: 'futsal',
              query: _query,
              searchController: _search,
              usingPreviewData: _usingPreviewData,
            ),
          ],
        ),
      ),
    );
  }

  String _titleForSport(String sport) => sport == 'tennis' ? '테니스 룰북' : '풋살 룰북';
}

class _RuleBookBody extends StatelessWidget {
  const _RuleBookBody({
    required this.grouped,
    required this.sport,
    required this.query,
    required this.searchController,
    required this.usingPreviewData,
  });

  final Map<String, List<RuleArticle>>? grouped;
  final String sport;
  final String query;
  final TextEditingController searchController;
  final bool usingPreviewData;

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered(grouped, query);

    if (grouped == null || grouped!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          _RuleSearchCard(controller: searchController, sport: sport),
          if (usingPreviewData) ...[
            const SizedBox(height: AppSpacing.sm),
            const _PreviewRulesBanner(),
          ],
          const SizedBox(height: AppSpacing.lg),
          _DailyRuleQuizCard(sport: sport),
          const SizedBox(height: AppSpacing.xl),
          const AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: '등록된 룰북이 없습니다',
            description: '관리자가 룰북을 등록하면 이곳에 표시됩니다.',
          ),
        ],
      );
    }

    final hasQuery = query.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxxl,
      ),
      children: [
        _RuleSearchCard(controller: searchController, sport: sport),
        if (usingPreviewData) ...[
          const SizedBox(height: AppSpacing.sm),
          const _PreviewRulesBanner(),
        ],
        if (!hasQuery) ...[
          const SizedBox(height: AppSpacing.lg),
          _DailyRuleQuizCard(sport: sport),
          const SizedBox(height: AppSpacing.xl),
          _CategoryGrid(grouped: grouped!, sport: sport),
        ],
        const SizedBox(height: AppSpacing.xl),
        _PopularRulesList(
          // 검색 결과는 잘리면 원하는 룰을 놓칠 수 있어 전체 표시, 기본은 상위 8개.
          articles: _popularArticles(
            hasQuery ? filtered : grouped!,
            limit: hasQuery ? null : 8,
          ),
          sport: sport,
          title: hasQuery ? '검색 결과' : '자주 찾는 룰',
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

  List<RuleArticle> _popularArticles(
    Map<String, List<RuleArticle>> source, {
    int? limit,
  }) {
    final all = source.values.expand((items) => items).toList();
    return limit == null ? all : all.take(limit).toList();
  }
}

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
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: index.isEven ? 0.72 : 0.56,
                child: Container(
                  height: 14,
                  color: cs.surfaceContainerHighest,
                ),
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
      if (!_shouldHideRuleCategory(sport, entry.key))
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

bool _shouldHideRuleCategory(String sport, String category) {
  return sport == 'futsal' && category.contains('연맹');
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
      decoration: InputDecoration(
        hintText: '룰 검색하기...',
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

class _PreviewRulesBanner extends StatelessWidget {
  const _PreviewRulesBanner();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '백엔드 연결 전 디자인 미리보기 룰북입니다.',
              style: tt.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyRuleQuizCard extends StatelessWidget {
  const _DailyRuleQuizCard({required this.sport});

  final String sport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final quiz = _quizForToday(sport);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showQuiz(context, quiz),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outline),
              bottom: BorderSide(color: cs.outline),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '오늘의 룰 퀴즈',
                      style: tt.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      quiz.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleQuiz {
  const _RuleQuiz({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

_RuleQuiz _quizForToday(String sport) {
  final quizzes = sport == 'futsal' ? _futsalQuizzes : _tennisQuizzes;
  final today = DateTime.now();
  final day = today.difference(DateTime(today.year, 1, 1)).inDays;
  return quizzes[day % quizzes.length];
}

const _futsalQuizzes = [
  _RuleQuiz(
    question: '풋살에서 골키퍼가 볼을 컨트롤할 수 있는 제한 시간은?',
    options: ['2초', '4초', '6초', '제한 없음'],
    correctIndex: 1,
    explanation: '풋살에서 골키퍼는 자기 진영에서 볼을 4초 넘게 컨트롤할 수 없습니다.',
  ),
  _RuleQuiz(
    question: '풋살 경기 중 선수 교체 횟수는 몇 번까지 가능할까요?',
    options: ['3번', '5번', '무제한', '7번'],
    correctIndex: 2,
    explanation: '풋살은 지정된 절차와 교체 구역을 지키면 경기 중 무제한 교체가 가능합니다.',
  ),
  _RuleQuiz(
    question: '볼이 터치라인을 넘었을 때 풋살의 재개 방법은?',
    options: ['스로인', '킥-인', '드롭 볼', '골 클리어런스'],
    correctIndex: 1,
    explanation: '풋살에서는 볼이 터치라인을 넘으면 손으로 던지지 않고 킥-인으로 재개합니다.',
  ),
];

const _tennisQuizzes = [
  _RuleQuiz(
    question: '테니스에서 세트 게임 스코어가 6-6이면 일반적으로 무엇을 할까요?',
    options: ['듀스', '타이브레이크', '렛', '세트 종료'],
    correctIndex: 1,
    explanation: '일반적인 세트에서는 6-6이 되면 타이브레이크로 세트 승자를 정합니다.',
  ),
  _RuleQuiz(
    question: '첫 서브와 두 번째 서브가 모두 폴트가 되면?',
    options: ['렛', '다시 서브', '상대 포인트', '게임 종료'],
    correctIndex: 2,
    explanation: '두 번의 서브 기회를 모두 실패한 더블 폴트는 상대방의 포인트가 됩니다.',
  ),
  _RuleQuiz(
    question: '공이 라인에 조금이라도 닿은 경우의 판정은?',
    options: ['아웃', '인', '렛', '재경기'],
    correctIndex: 1,
    explanation: '테니스에서는 공이 라인에 닿으면 인으로 판정합니다.',
  ),
];

void _showQuiz(BuildContext context, _RuleQuiz quiz) {
  var selectedIndex = -1;
  var revealed = false;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          title: Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: cs.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '오늘의 룰 퀴즈',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quiz.question,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var index = 0; index < quiz.options.length; index++) ...[
                  _QuizOption(
                    number: index + 1,
                    label: quiz.options[index],
                    selected: selectedIndex == index,
                    correct: revealed && quiz.correctIndex == index,
                    wrong: revealed &&
                        selectedIndex == index &&
                        quiz.correctIndex != index,
                    onTap: revealed
                        ? null
                        : () => setDialogState(() => selectedIndex = index),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (revealed) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: selectedIndex == quiz.correctIndex
                          ? cs.primaryContainer
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Text(
                      quiz.explanation,
                      style: tt.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(revealed ? '닫기' : '취소'),
            ),
            if (!revealed)
              FilledButton(
                onPressed: selectedIndex < 0
                    ? null
                    : () => setDialogState(() => revealed = true),
                child: const Text('정답 확인'),
              ),
          ],
        );
      },
    ),
  );
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.number,
    required this.label,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = correct
        ? cs.secondary
        : wrong
            ? cs.error
            : selected
                ? cs.primary
                : cs.outlineVariant;
    final background = correct
        ? cs.secondaryContainer
        : wrong
            ? cs.errorContainer
            : selected
                ? cs.primaryContainer
                : cs.surfaceContainerLow;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
                color: color, width: selected || correct || wrong ? 2 : 1),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: color,
                child: Text(
                  '$number',
                  style: tt.labelSmall?.copyWith(
                    color: correct || wrong || selected
                        ? Colors.white
                        : cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (correct) Icon(Icons.check_rounded, color: cs.secondary),
              if (wrong) Icon(Icons.close_rounded, color: cs.error),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.grouped, required this.sport});

  final Map<String, List<RuleArticle>> grouped;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final entries = grouped.entries.toList();
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          _CategoryCard(
            title: entries[index].key,
            count: entries[index].value.length,
            icon: _iconForCategory(entries[index].key),
            sport: sport,
            onTap: () => _showCategorySheet(
              context,
              entries[index].key,
              entries[index].value,
              sport,
            ),
          ),
          if (index < entries.length - 1)
            Divider(height: 1, color: cs.outlineVariant),
        ],
      ],
    );
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
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.sport,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final String sport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = _accentFor(context, sport);
    final description = _descriptionForCategory(title);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.listRow + AppSpacing.lg,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: AppSizes.touchTarget,
                  height: AppSizes.touchTarget,
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$description · $count개 규칙',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        for (var index = 0; index < articles.length; index++) ...[
          _ArticleRow(article: articles[index], index: index, sport: sport),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    required this.article,
    required this.index,
    required this.sport,
  });

  final RuleArticle article;
  final int index;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = _accentFor(context, sport);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showArticle(context, article),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: tt.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  article.title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategorySheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = _accentFor(context, sport);

    return ListView(
      controller: scrollController,
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
        Row(
          children: [
            Icon(_iconForCategory(title), color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var index = 0; index < articles.length; index++) ...[
          _ArticleRow(article: articles[index], index: index, sport: sport),
          const SizedBox(height: AppSpacing.sm),
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
          data: '# ${article.title}\n\n${article.body}',
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
    return '풋살공 · 피치 · 장비';
  }
  if (lower.contains('연맹')) {
    return '공식 기관 · 규칙서';
  }
  if (lower.contains('포지션') || lower.contains('전술')) {
    return '피보 · 아라 · 픽소';
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
