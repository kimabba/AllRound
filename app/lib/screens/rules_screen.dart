import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tournament.dart';
import '../state/providers.dart';
import '../theme/tokens.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, List<RuleArticle>>? _tennisByCat;
  Map<String, List<RuleArticle>>? _futsalByCat;
  Map<String, List<RuleArticle>>? _activeByCat; // 단일 종목용
  String? _activeSport; // 로드 시점의 activeSport 저장
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final sport = ref.read(activeSportProvider);
    _activeSport = sport;

    if (sport != null) {
      // 활성 종목만 fetch
      final rules = await api.listRules(sport);
      if (!mounted) return;
      setState(() {
        _activeByCat = _groupByCategory(rules);
        _loading = false;
      });
    } else {
      // 미등록: 두 종목 모두 fetch
      final tennis = await api.listRules('tennis');
      final futsal = await api.listRules('futsal');
      if (!mounted) return;
      setState(() {
        _tennisByCat = _groupByCategory(tennis);
        _futsalByCat = _groupByCategory(futsal);
        _loading = false;
      });
    }
  }

  Map<String, List<RuleArticle>> _groupByCategory(List<RuleArticle> list) {
    final out = <String, List<RuleArticle>>{};
    for (final r in list) {
      out.putIfAbsent(r.category, () => []).add(r);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeSportProvider, (_, __) {
      setState(() => _loading = true);
      _load();
    });

    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 활성 종목 있음: 단일 ListView
    if (_activeSport != null && _activeByCat != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('룰북')),
        body: _CategoryList(grouped: _activeByCat),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('룰북'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(
              icon: Icon(Icons.sports_tennis_rounded),
              text: '테니스',
            ),
            Tab(
              icon: Icon(Icons.sports_soccer_rounded),
              text: '풋살',
            ),
          ],
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _CategoryList(grouped: _tennisByCat),
          _CategoryList(grouped: _futsalByCat),
        ],
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final Map<String, List<RuleArticle>>? grouped;
  const _CategoryList({this.grouped});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (grouped == null || grouped!.isEmpty) {
      return const Center(child: Text('등록된 룰북이 없습니다.'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final entry in grouped!.entries)
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              title: Text(
                entry.key,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              iconColor: cs.primary,
              collapsedIconColor: cs.onSurfaceVariant,
              childrenPadding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              children: [
                for (final article in entry.value)
                  _ArticleTile(article: article),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArticleTile extends StatelessWidget {
  final RuleArticle article;
  const _ArticleTile({required this.article});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _showArticle(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(Icons.article_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(article.title, style: tt.bodyMedium)),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _showArticle(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
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
}
