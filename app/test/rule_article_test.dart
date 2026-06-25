import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';

void main() {
  test('RuleArticle.fromJson parses new admin fields', () {
    final r = RuleArticle.fromJson({
      'id': 'r1',
      'sport': 'tennis',
      'category': '서브',
      'title': '서브 규칙',
      'body': '## 서브\n본문',
      'order_idx': 3,
      'published': false,
      'embedding_updated_at': '2026-05-27T00:00:00Z',
      'updated_at': '2026-05-27T01:00:00Z',
    });
    expect(r.orderIdx, 3);
    expect(r.published, false);
    expect(r.embeddingPending, false);
  });

  test('RuleArticle.fromJson stays compatible with legacy rows (no new fields)', () {
    final r = RuleArticle.fromJson({
      'id': 'r2', 'sport': 'futsal', 'category': '파울',
      'title': 't', 'body': 'b',
    });
    expect(r.orderIdx, 0);
    expect(r.published, true);
    expect(r.embeddingPending, true); // embedding_updated_at 없음 → 대기
  });
}
