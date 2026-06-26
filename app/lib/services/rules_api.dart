import 'package:http/http.dart' as http;

import '../models/tournament.dart';
import 'api_base.dart';

/// 규정(rule_articles) CRUD API.
mixin RulesApi on ApiBase {
  Future<List<RuleArticle>> listRules(String sport) async {
    final rows = await supabase
        .from('rule_articles')
        .select()
        .eq('sport', sport)
        .eq('published', true)
        .order('order_idx');
    return rows.map((r) => RuleArticle.fromJson(r)).toList();
  }

  Future<List<RuleArticle>> adminListRules({String? sport}) async {
    var q = supabase.from('rule_articles').select(
          'id, sport, category, title, body, order_idx, published, embedding_updated_at, updated_at',
        );
    if (sport != null) q = q.eq('sport', sport);
    final rows = await q.order('sport').order('category').order('order_idx');
    return (rows as List)
        .map((r) => RuleArticle.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createRule(Map<String, dynamic> data) async {
    await supabase.from('rule_articles').insert(data);
  }

  Future<void> updateRule(String id, Map<String, dynamic> data) async {
    await supabase.from('rule_articles').update(data).eq('id', id);
  }

  Future<void> deleteRule(String id) async {
    await supabase.from('rule_articles').delete().eq('id', id);
  }

  Future<int> nextRuleOrderIdx(String sport, String category) async {
    final rows = await supabase
        .from('rule_articles')
        .select('order_idx')
        .eq('sport', sport)
        .eq('category', category)
        .order('order_idx', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return 0;
    return ((list.first['order_idx'] as int?) ?? 0) + 1;
  }

  Future<void> recomputeRuleEmbedding(String id) async {
    await supabase
        .from('rule_articles')
        .update({'embedding': null, 'embedding_updated_at': null}).eq('id', id);
    final res = await http.post(
      uri('embed-pending'),
      headers: await authHeaders(),
    );
    check(res);
  }
}
