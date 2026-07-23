import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tournament.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart';
import 'rule_edit_screen.dart';

class KnowledgeBaseTab extends ConsumerStatefulWidget {
  const KnowledgeBaseTab({super.key});

  @override
  ConsumerState<KnowledgeBaseTab> createState() => _KnowledgeBaseTabState();
}

class _KnowledgeBaseTabState extends ConsumerState<KnowledgeBaseTab> {
  String? _sportFilter; // null=전체

  Future<void> _openEditor(List<RuleArticle> all, {RuleArticle? rule}) async {
    final cats = all.map((r) => r.category).toSet().toList()..sort();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RuleEditScreen(rule: rule, existingCategories: cats),
      ),
    );
    if (changed == true) ref.invalidate(adminRulesProvider(_sportFilter));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rulesAsync = ref.watch(adminRulesProvider(_sportFilter));

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<String?>(
              segments: [
                const ButtonSegment(value: null, label: Text('전체')),
                ButtonSegment(
                    value: 'tennis',
                    label: Text(sportLabelFromString('tennis'))),
                ButtonSegment(
                    value: 'futsal',
                    label: Text(sportLabelFromString('futsal'))),
              ],
              selected: {_sportFilter},
              onSelectionChanged: (s) => setState(() => _sportFilter = s.first),
            ),
          ),
          Expanded(
            child: rulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('로드 실패: $e')),
              data: (rules) => rules.isEmpty
                  ? const Center(child: Text('문서가 없습니다'))
                  : ListView.builder(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: rules.length,
                      itemBuilder: (_, i) {
                        final r = rules[i];
                        return Card(
                          child: ListTile(
                            title: Text(r.title),
                            subtitle: Text(
                                '${sportLabelFromString(r.sport)} · ${r.category}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!r.published)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: AppSpacing.sm),
                                    child: Text('미게시',
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant)),
                                  ),
                                _EmbeddingBadge(pending: r.embeddingPending),
                              ],
                            ),
                            onTap: () => _openEditor(rules, rule: r),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: rulesAsync.maybeWhen(
        data: (rules) => FloatingActionButton.extended(
          onPressed: () => _openEditor(rules),
          icon: const Icon(Icons.add_rounded),
          label: const Text('문서 작성'),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _EmbeddingBadge extends StatelessWidget {
  final bool pending;
  const _EmbeddingBadge({required this.pending});

  @override
  Widget build(BuildContext context) {
    final color = pending ? Colors.orange : Colors.green;
    final label = pending ? '임베딩 대기' : '최신';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
