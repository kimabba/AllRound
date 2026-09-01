import '../models/rule_popularity.dart';
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
    var q = supabase
        .from('rule_articles')
        .select(
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
        .update({'embedding': null, 'embedding_updated_at': null})
        .eq('id', id);
    final res = await httpPost(
      uri('embed-pending'),
      headers: await authHeaders(),
    );
    check(res);
  }

  /// 같은 사용자·규칙은 서버에서 최근 24시간에 한 번만 유효 클릭으로 기록한다.
  Future<bool> recordRuleArticleClick(String articleId) async {
    final raw = await supabase.rpc(
      'record_rule_article_click',
      params: {'p_article_id': articleId},
    );
    if (raw is! bool) {
      throw const FormatException('룰 클릭 기록 결과가 올바르지 않습니다.');
    }
    return raw;
  }

  /// 최근 24시간 카테고리 합계가 가장 높은 분류와 그 안의 최다 클릭 규칙.
  Future<RulePopularityHighlight?> popularRuleHighlight24h(String sport) async {
    final raw = await supabase.rpc(
      'popular_rule_highlight_24h',
      params: {'p_sport': sport},
    );
    if (raw is! List) {
      throw const FormatException('인기 룰 조회 결과가 올바르지 않습니다.');
    }
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) {
      throw const FormatException('인기 룰 항목이 올바르지 않습니다.');
    }
    return RulePopularityHighlight.fromJson(Map<String, dynamic>.from(first));
  }
}
