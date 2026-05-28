import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/matchup_logo.dart';

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

    try {
      if (sport != null) {
        final rules = await api.listRules(sport);
        if (!mounted) return;
        setState(() {
          _activeByCat = _groupByCategory(rules);
          _loading = false;
        });
      } else {
        final tennis = await api.listRules('tennis');
        final futsal = await api.listRules('futsal');
        if (!mounted) return;
        setState(() {
          _tennisByCat = _groupByCategory(tennis);
          _futsalByCat = _groupByCategory(futsal);
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
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
    ref.listen(activeSportProvider, (_, __) => _load());

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
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
        appBar: AppBar(
          title: BrandedAppBarTitle(title: _titleForSport(_activeSport!)),
        ),
        body: _RuleBookBody(
          grouped: _activeByCat,
          sport: _activeSport!,
          query: _query,
          searchController: _search,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const BrandedAppBarTitle(title: '룰북'),
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
      body: TabBarView(
        controller: _tab,
        children: [
          _RuleBookBody(
            grouped: _tennisByCat,
            sport: 'tennis',
            query: _query,
            searchController: _search,
          ),
          _RuleBookBody(
            grouped: _futsalByCat,
            sport: 'futsal',
            query: _query,
            searchController: _search,
          ),
        ],
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
  });

  final Map<String, List<RuleArticle>>? grouped;
  final String sport;
  final String query;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered(grouped, query);

    if (grouped == null || grouped!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        _RuleSearchCard(controller: searchController, sport: sport),
        const SizedBox(height: AppSpacing.lg),
        _DailyRuleQuizCard(sport: sport),
        const SizedBox(height: AppSpacing.xl),
        _CategoryGrid(grouped: grouped!, sport: sport),
        const SizedBox(height: AppSpacing.xl),
        _PopularRulesList(articles: _popularArticles(filtered), sport: sport),
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
        return categoryMatches || article.title.toLowerCase().contains(lower);
      }).toList();
      if (articles.isNotEmpty) out[entry.key] = articles;
    }
    return out;
  }

  List<RuleArticle> _popularArticles(Map<String, List<RuleArticle>> source) {
    return source.values.expand((items) => items).take(8).toList();
  }
}

class _RuleSearchCard extends StatelessWidget {
  const _RuleSearchCard({required this.controller, required this.sport});

  final TextEditingController controller;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _accentFor(context, sport);

    return AppCard(
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: '룰 검색하기',
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          suffixIcon: Icon(
            sport == 'tennis'
                ? Icons.sports_tennis_rounded
                : Icons.sports_soccer_rounded,
            color: accent,
          ),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    );
  }
}

class _DailyRuleQuizCard extends StatelessWidget {
  const _DailyRuleQuizCard({required this.sport});

  final String sport;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final quiz = _quizForToday(sport);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        height: 126,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/rules/rule-quiz-cover.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: InkWell(
          onTap: () => _showQuiz(context, quiz),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xF20A1832),
                  Color(0xC90A1832),
                  Color(0x250A1832),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9F84B),
                            borderRadius: AppRadius.pill,
                          ),
                          child: Text(
                            'TODAY QUIZ',
                            style: tt.labelSmall?.copyWith(
                              color: const Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '오늘의 룰 퀴즈',
                          style: tt.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          quiz.question,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '오늘의 룰 퀴즈',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
                          ? const Color(0xFFECFCCB)
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.w900,
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

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _CategoryCard(
          title: entry.key,
          count: entry.value.length,
          icon: _iconForCategory(entry.key),
          sport: sport,
          onTap: () =>
              _showCategorySheet(context, entry.key, entry.value, sport),
        );
      },
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
    final accentContainer = _accentContainerFor(context, sport);

    return AppCard(
      onTap: onTap,
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const Spacer(),
          Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '$count개 규칙',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PopularRulesList extends StatelessWidget {
  const _PopularRulesList({required this.articles, required this.sport});

  final List<RuleArticle> articles;
  final String sport;

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
          '자주 찾는 룰',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
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
    final accentContainer = _accentContainerFor(context, sport);

    return AppCard(
      onTap: () => _showArticle(context, article),
      variant: AppCardVariant.elevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: tt.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
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
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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

Color _accentFor(BuildContext context, String sport) {
  final cs = Theme.of(context).colorScheme;
  return sport == 'tennis' ? cs.tertiary : cs.secondary;
}

Color _accentContainerFor(BuildContext context, String sport) {
  final cs = Theme.of(context).colorScheme;
  return sport == 'tennis' ? cs.tertiaryContainer : cs.secondaryContainer;
}
