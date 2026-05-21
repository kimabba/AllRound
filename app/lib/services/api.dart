import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/admin.dart';
import '../models/crawl_source.dart';
import '../models/tournament.dart';

/// Edge Functions REST + SSE 클라이언트.
class ApiService {
  ApiService(this._supabase);

  final SupabaseClient _supabase;

  Future<Map<String, String>> _authHeaders() async {
    final session = _supabase.auth.currentSession;
    String? token = session?.accessToken;
    if (session != null && session.isExpired) {
      final refreshed = await _supabase.auth.refreshSession();
      token = refreshed.session?.accessToken;
    }
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    return base.replace(
      path: '${base.path}/$path',
      queryParameters: query?..removeWhere((_, v) => v.isEmpty),
    );
  }

  // ===== tournaments =====

  Future<List<Tournament>> searchTournaments({
    String? sport,
    String? region,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool onlyMyGrade = true,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await http.get(
      _uri('tournaments-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (dateFrom != null) 'date_from': _ymd(dateFrom),
        if (dateTo != null) 'date_to': _ymd(dateTo),
        'only_my_grade': onlyMyGrade.toString(),
        if (query != null && query.isNotEmpty) 'q': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
      }),
      headers: await _authHeaders(),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['tournaments'] as List)
        .map((e) => Tournament.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Tournament> submitTournament(Map<String, dynamic> payload) async {
    final res = await http.post(
      _uri('tournaments-submit'),
      headers: await _authHeaders(),
      body: jsonEncode(payload),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Tournament.fromJson(body['tournament'] as Map<String, dynamic>);
  }

  Future<void> approveTournament(String id, {bool approve = true, String? reason}) async {
    final res = await http.post(
      _uri('tournaments-approve'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'id': id,
        'action': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      }),
    );
    _check(res);
  }

  // ===== favorites =====
  Future<void> toggleFavorite(String tournamentId, bool favorite) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    if (favorite) {
      await _supabase.from('tournament_favorites').upsert({
        'user_id': userId,
        'tournament_id': tournamentId,
      });
    } else {
      await _supabase
          .from('tournament_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('tournament_id', tournamentId);
    }
  }

  Future<Set<String>> myFavoriteIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await _supabase
        .from('tournament_favorites')
        .select('tournament_id')
        .eq('user_id', userId);
    return rows.map((r) => r['tournament_id'] as String).toSet();
  }

  // ===== clubs =====
  Future<List<Club>> searchClubs({String? sport, String? region, String? q}) async {
    final res = await http.get(
      _uri('clubs-search', {
        if (sport != null) 'sport': sport,
        if (region != null) 'region': region,
        if (q != null && q.isNotEmpty) 'q': q,
      }),
      headers: await _authHeaders(),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ===== rules =====
  Future<List<RuleArticle>> listRules(String sport) async {
    final rows = await _supabase
        .from('rule_articles')
        .select()
        .eq('sport', sport)
        .eq('published', true)
        .order('order_idx');
    return rows.map((r) => RuleArticle.fromJson(r)).toList();
  }

  // ===== chat (SSE) =====

  /// SSE 스트리밍. 이벤트 라인을 yield 한다.
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
  }) async* {
    final request = http.Request('POST', _uri('chat'));
    final headers = await _authHeaders();
    request.headers.addAll({
      ...headers,
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      'enable_search': enableSearch,
    });

    final client = http.Client();
    try {
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.transform(utf8.decoder).join();
        throw Exception('chat ${streamed.statusCode}: $body');
      }
      String buffer = '';
      String currentEvent = 'message';
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx < 0) break;
          final block = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              final raw = line.substring(5).trim();
              if (raw.isEmpty) continue;
              try {
                final data = jsonDecode(raw) as Map<String, dynamic>;
                yield ChatStreamEvent(currentEvent, data);
              } catch (_) {/* skip malformed chunk */}
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }

  // ===== devices =====
  Future<void> registerDeviceToken(String token, String platform) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'enabled': true,
    });
  }

  // ===== user_sports =====
  Future<List<UserSport>> myUserSports() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('user_sports')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserSport.fromJson(r)).toList();
  }

  Future<void> saveUserSports(List<UserSport> sports) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    // public.users 행이 없으면 자동 생성 (세션 캐시 불일치 방지)
    await _supabase.rpc('ensure_profile');
    await _supabase.from('user_sports').delete().eq('user_id', userId);
    if (sports.isNotEmpty) {
      await _supabase
          .from('user_sports')
          .insert(sports.map((s) => s.toInsert(userId)).toList());
    }
  }

  // ===== regions =====
  Future<List<Region>> listRegions() async {
    final rows = await _supabase.from('regions').select().order('code');
    return rows.map((r) => Region.fromJson(r)).toList();
  }

  // ===== user_tennis_orgs (multi-org) =====
  Future<List<UserTennisOrg>> myTennisOrgs() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('user_tennis_orgs')
        .select()
        .eq('user_id', userId)
        .order('is_primary', ascending: false);
    return rows.map((r) => UserTennisOrg.fromJson(r)).toList();
  }

  /// 협회 등록을 일괄 갱신 (delete-all-then-insert).
  /// 한 번에 N개 협회를 등록할 때 사용.
  Future<void> saveTennisOrgs(List<UserTennisOrg> orgs) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await _supabase.from('user_tennis_orgs').delete().eq('user_id', userId);
    if (orgs.isNotEmpty) {
      await _supabase
          .from('user_tennis_orgs')
          .insert(orgs.map((o) => o.toUpsert(userId)).toList());
    }
  }

  /// 단일 협회 추가/갱신 (upsert).
  Future<void> upsertTennisOrg(UserTennisOrg org) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await _supabase.from('user_tennis_orgs').upsert(org.toUpsert(userId));
  }

  /// 단일 협회 삭제.
  Future<void> deleteTennisOrg(String org) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    await _supabase
        .from('user_tennis_orgs')
        .delete()
        .eq('user_id', userId)
        .eq('org', org);
  }

  // ===== admin =====
  Future<List<CrawlAuditLog>> crawlAuditLogs({int limit = 30}) async {
    final rows = await _supabase
        .from('crawl_audit')
        .select()
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map((r) => CrawlAuditLog.fromJson(r)).toList();
  }

  Future<Map<String, dynamic>> invokeCrawler(String source) async {
    final res = await http.post(
      _uri(source),
      headers: await _authHeaders(),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ===== admin: crawl_sources (RLS 가 admin role 만 허용 → REST 직접 사용) =====

  Future<List<CrawlSource>> crawlSources() async {
    final rows = await _supabase
        .from('crawl_sources')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows)
        .map(CrawlSource.fromJson)
        .toList();
  }

  Future<CrawlSource> createCrawlSource({
    required String name,
    required String slug,
    required String url,
    String? sport,
    String? region,
    String sourceType = 'board',
    required String parserModule,
    String scheduleCron = '0 21 * * *',
    bool enabled = true,
    String? notes,
  }) async {
    final row = await _supabase
        .from('crawl_sources')
        .insert({
          'name': name,
          'slug': slug,
          'url': url,
          if (sport != null && sport.isNotEmpty) 'sport': sport,
          if (region != null && region.isNotEmpty) 'region': region,
          'source_type': sourceType,
          'parser_module': parserModule,
          'schedule_cron': scheduleCron,
          'enabled': enabled,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        })
        .select()
        .single();
    return CrawlSource.fromJson(row);
  }

  Future<CrawlSource> updateCrawlSource(
    String id, {
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
  }) async {
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
    if (patch.isEmpty) {
      // nothing to update — re-fetch row so caller can refresh
      final row = await _supabase
          .from('crawl_sources')
          .select()
          .eq('id', id)
          .single();
      return CrawlSource.fromJson(row);
    }
    final row = await _supabase
        .from('crawl_sources')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return CrawlSource.fromJson(row);
  }

  Future<void> deleteCrawlSource(String id) async {
    await _supabase.from('crawl_sources').delete().eq('id', id);
  }

  Future<CrawlSource> toggleCrawlSourceEnabled(String id, bool enabled) async {
    return updateCrawlSource(id, enabled: enabled);
  }

  /// Phase 2: 어드민 "수동 실행" → crawl-dispatch 단일 진입점 호출.
  /// force=true 면 schedule_cron 무시하고 즉시 실행 (수동 트리거 의도).
  ///
  /// 응답 예시:
  ///   { executed: [{ slug, status, fetched_count, inserted_count, ... }],
  ///     skipped: [...], errors: [...] }
  Future<Map<String, dynamic>> runCrawlSource(
    String slug, {
    bool force = true,
  }) async {
    final res = await http.post(
      _uri('crawl-dispatch'),
      headers: await _authHeaders(),
      body: jsonEncode({'slug': slug, 'force': force}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ===== helpers =====
  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _check(http.Response res) {
    if (res.statusCode >= 400) {
      throw Exception('${res.statusCode}: ${res.body}');
    }
  }
}

class ChatStreamEvent {
  final String event;
  final Map<String, dynamic> data;
  ChatStreamEvent(this.event, this.data);
}
