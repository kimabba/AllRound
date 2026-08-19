class RulePopularityHighlight {
  const RulePopularityHighlight({
    required this.articleId,
    required this.sport,
    required this.category,
    required this.title,
    required this.articleClickCount,
    required this.categoryClickCount,
    required this.windowStartedAt,
  });

  final String articleId;
  final String sport;
  final String category;
  final String title;
  final int articleClickCount;
  final int categoryClickCount;
  final DateTime windowStartedAt;

  factory RulePopularityHighlight.fromJson(Map<String, dynamic> json) {
    return RulePopularityHighlight(
      articleId: json['article_id'] as String,
      sport: json['sport'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      articleClickCount: (json['article_click_count'] as num).toInt(),
      categoryClickCount: (json['category_click_count'] as num).toInt(),
      windowStartedAt: DateTime.parse(json['window_started_at'] as String),
    );
  }
}
