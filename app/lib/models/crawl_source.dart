/// 어드민이 관리하는 크롤링 소스 행 (public.crawl_sources).
///
/// Phase 1 범위:
///   - 목록 표시 + CRUD + enabled 토글.
///   - last_* 운영 메트릭은 read-only (Phase 2 dispatcher 가 갱신).
class CrawlSource {
  final String id;
  final String name;
  final String slug;
  final String url;
  final String? sport; // 'tennis' | 'futsal' | null
  final String? region;
  final String sourceType; // 'board' | 'rss' | 'json_api' | 'sitemap'
  final String parserModule;
  final String scheduleCron;
  final bool enabled;
  final DateTime? lastCrawledAt;
  final String? lastStatus;
  final String? lastError;
  final int? lastFetchedCount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CrawlSource({
    required this.id,
    required this.name,
    required this.slug,
    required this.url,
    required this.sport,
    required this.region,
    required this.sourceType,
    required this.parserModule,
    required this.scheduleCron,
    required this.enabled,
    required this.lastCrawledAt,
    required this.lastStatus,
    required this.lastError,
    required this.lastFetchedCount,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CrawlSource.fromJson(Map<String, dynamic> j) => CrawlSource(
        id: j['id'] as String,
        name: j['name'] as String,
        slug: j['slug'] as String,
        url: j['url'] as String,
        sport: j['sport'] as String?,
        region: j['region'] as String?,
        sourceType: j['source_type'] as String? ?? 'board',
        parserModule: j['parser_module'] as String,
        scheduleCron: j['schedule_cron'] as String? ?? '0 21 * * *',
        enabled: j['enabled'] as bool? ?? true,
        lastCrawledAt: j['last_crawled_at'] != null
            ? DateTime.parse(j['last_crawled_at'] as String)
            : null,
        lastStatus: j['last_status'] as String?,
        lastError: j['last_error'] as String?,
        lastFetchedCount: j['last_fetched_count'] as int?,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );

  /// INSERT 시 사용 (id / created_at / updated_at / last_* 제외).
  Map<String, dynamic> toInsert() => {
        'name': name,
        'slug': slug,
        'url': url,
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        'source_type': sourceType,
        'parser_module': parserModule,
        'schedule_cron': scheduleCron,
        'enabled': enabled,
        if (notes != null) 'notes': notes,
      };

  /// 부분 UPDATE 시 사용 (null 인 필드는 제외).
  /// enabled / notes 등 단일 필드만 패치할 때도 사용.
  Map<String, dynamic> toUpdatePatch({
    String? name,
    String? url,
    String? sport,
    String? region,
    String? sourceType,
    String? parserModule,
    String? scheduleCron,
    bool? enabled,
    String? notes,
    bool clearSport = false,
    bool clearRegion = false,
    bool clearNotes = false,
  }) {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (url != null) patch['url'] = url;
    if (clearSport) {
      patch['sport'] = null;
    } else if (sport != null) {
      patch['sport'] = sport;
    }
    if (clearRegion) {
      patch['region'] = null;
    } else if (region != null) {
      patch['region'] = region;
    }
    if (sourceType != null) patch['source_type'] = sourceType;
    if (parserModule != null) patch['parser_module'] = parserModule;
    if (scheduleCron != null) patch['schedule_cron'] = scheduleCron;
    if (enabled != null) patch['enabled'] = enabled;
    if (clearNotes) {
      patch['notes'] = null;
    } else if (notes != null) {
      patch['notes'] = notes;
    }
    return patch;
  }
}
