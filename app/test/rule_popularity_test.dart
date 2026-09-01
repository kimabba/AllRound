import 'package:allround/models/rule_popularity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('최근 24시간 인기 룰 RPC 응답을 타입 모델로 변환한다', () {
    final highlight = RulePopularityHighlight.fromJson({
      'article_id': 'article-1',
      'sport': 'futsal',
      'category': '파울',
      'title': '누적 파울',
      'article_click_count': 12,
      'category_click_count': 31,
      'window_started_at': '2026-08-18T12:00:00Z',
    });

    expect(highlight.articleId, 'article-1');
    expect(highlight.sport, 'futsal');
    expect(highlight.category, '파울');
    expect(highlight.articleClickCount, 12);
    expect(highlight.categoryClickCount, 31);
    expect(highlight.windowStartedAt, DateTime.utc(2026, 8, 18, 12));
  });
}
