import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/admin.dart';
import '../models/club_event.dart';
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

  Future<void> approveTournament(String id,
      {bool approve = true, String? reason}) async {
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

  // ===== admin: review queue (Phase 3) =====

  /// Draft 대회 목록 — admin 전용.
  /// view 대신 tournaments 직접 조회 (view의 is_admin() WHERE절이
  /// PostgREST 컨텍스트에서 올바르게 평가되지 않는 문제 우회).
  /// RLS tournaments_published_read 가 is_admin() 케이스를 이미 허용.
  Future<List<Map<String, dynamic>>> tournamentReviewQueue() async {
    final rows = await _supabase
        .from('tournaments')
        .select(
          'id, sport, title, organizer, description, start_date, end_date, '
          'application_deadline, region, location, eligible_grades, entry_fee, '
          'format, source, source_url, submitted_by, created_at',
        )
        .eq('status', 'draft')
        .order('created_at', ascending: false);
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final src = m['source'] as String? ?? '';
      final submittedBy = m['submitted_by'];
      m['submission_kind'] = (src == 'user_submission' || submittedBy != null)
          ? 'user'
          : 'crawler';
      m['submitted_by_email'] = null;
      return m;
    }).toList();
  }

  /// `tournaments_bulk_approve` RPC — admin 만 호출 가능.
  /// 반환값은 실제 update 된 행 수.
  Future<int> bulkApproveTournaments(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final res =
        await _supabase.rpc('tournaments_bulk_approve', params: {'p_ids': ids});
    return (res as num).toInt();
  }

  /// `tournaments_bulk_reject` RPC — admin 만 호출 가능, reason 필수.
  /// 반환값은 실제 update 된 행 수.
  Future<int> bulkRejectTournaments(List<String> ids, String reason) async {
    if (ids.isEmpty) return 0;
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('rejection reason required');
    }
    final res = await _supabase.rpc(
      'tournaments_bulk_reject',
      params: {'p_ids': ids, 'p_reason': trimmed},
    );
    return (res as num).toInt();
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

  Future<List<Tournament>> myFavoriteTournaments({int limit = 5}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('tournament_favorites')
        .select('created_at, tournaments(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((row) => row as Map<String, dynamic>)
        .map((row) => row['tournaments'])
        .whereType<Map<String, dynamic>>()
        .map(Tournament.fromJson)
        .toList();
  }

  Future<void> toggleClubFavorite(String clubId, bool favorite) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    if (favorite) {
      await _supabase.from('club_favorites').upsert({
        'user_id': userId,
        'club_id': clubId,
      });
    } else {
      await _supabase
          .from('club_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('club_id', clubId);
    }
  }

  Future<Set<String>> myClubFavoriteIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await _supabase
        .from('club_favorites')
        .select('club_id')
        .eq('user_id', userId);
    return rows.map((r) => r['club_id'] as String).toSet();
  }

  Future<List<Club>> myFavoriteClubs({int limit = 50}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _supabase
        .from('club_favorites')
        .select('created_at, clubs(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((row) => row as Map<String, dynamic>)
        .map((row) => row['clubs'])
        .whereType<Map<String, dynamic>>()
        .map(Club.fromJson)
        .toList();
  }

  // ===== clubs =====
  Future<List<Club>> searchClubs(
      {String? sport, String? region, String? q}) async {
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

  Future<List<Club>> myClubs() async {
    final res = await http.get(
      _uri('clubs-search', {'mine': 'true'}),
      headers: await _authHeaders(),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clubs'] as List)
        .map((e) => Club.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Club> createClub({
    required String sport,
    required String name,
    String? region,
    String? address,
    String? logoUrl,
    String? contact,
    String? website,
    String? description,
  }) async {
    final res = await http.post(
      _uri('clubs-create'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'sport': sport,
        'name': name,
        if (region != null && region.isNotEmpty) 'region': region,
        if (address != null && address.isNotEmpty) 'address': address,
        if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (website != null && website.isNotEmpty) 'website': website,
        if (description != null && description.isNotEmpty)
          'description': description,
      }),
    );
    _check(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return Club.fromJson(body['club'] as Map<String, dynamic>);
  }

  Future<String> uploadClubLogo({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    final safeExt = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final ext = safeExt.isEmpty ? 'jpg' : safeExt.toLowerCase();
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage.from('club-logos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    return _supabase.storage.from('club-logos').getPublicUrl(path);
  }

  Future<void> joinClub(String clubId, {String? message}) async {
    final res = await http.post(
      _uri('clubs-join'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'request',
        if (message != null && message.isNotEmpty) 'message': message,
      }),
    );
    _check(res);
  }

  Future<void> cancelJoinClub(String clubId) async {
    final res = await http.post(
      _uri('clubs-join'),
      headers: await _authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'cancel'}),
    );
    _check(res);
  }

  Future<void> leaveClub(String clubId) async {
    final res = await http.post(
      _uri('clubs-join'),
      headers: await _authHeaders(),
      body: jsonEncode({'club_id': clubId, 'action': 'leave'}),
    );
    _check(res);
  }

  Future<void> kickMember(String clubId, String targetUserId) async {
    final res = await http.post(
      _uri('clubs-join'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': 'kick',
        'target_user_id': targetUserId,
      }),
    );
    _check(res);
  }

  /// 클럽 가입 신청 목록 조회 (owner/manager 전용).
  Future<List<Map<String, dynamic>>> pendingJoinRequests(String clubId) async {
    final rows = await _supabase
        .from('club_join_requests')
        .select('id, user_id, message, created_at, users(display_name, email)')
        .eq('club_id', clubId)
        .eq('status', 'pending')
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> reviewJoinRequest(String requestId,
      {required bool approve, String? reason}) async {
    final res = await http.post(
      _uri('clubs-review-join'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'request_id': requestId,
        'action': approve ? 'approve' : 'reject',
        if (reason != null) 'reason': reason,
      }),
    );
    _check(res);
  }

  // ===== club activity (members / events) =====

  /// 클럽 active 멤버 목록 (owner → manager → member 순).
  Future<List<ClubMember>> clubMembers(String clubId) async {
    final rows = await _supabase
        .from('club_members')
        .select('user_id, role, joined_at, users(display_name)')
        .eq('club_id', clubId)
        .eq('status', 'active')
        .order('joined_at');
    final members =
        List<Map<String, dynamic>>.from(rows).map(ClubMember.fromJson).toList();
    const rank = {'owner': 0, 'manager': 1, 'member': 2};
    members.sort((a, b) => (rank[a.role] ?? 3).compareTo(rank[b.role] ?? 3));
    return members;
  }

  /// 다가오는 모임 일정 (참석자 수 + 본인 응답 포함).
  Future<List<ClubEvent>> clubEvents(String clubId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await _supabase
        .from('club_events')
        .select('*, club_event_attendees(user_id, status)')
        .eq('club_id', clubId)
        .gte('starts_at', nowIso)
        .order('starts_at');
    final uid = _supabase.auth.currentUser?.id;
    return List<Map<String, dynamic>>.from(rows)
        .map((j) => ClubEvent.fromJson(j, currentUserId: uid))
        .toList();
  }

  /// 모임 생성. type='official'은 운영진만(서버 RLS 가 강제).
  Future<void> createClubEvent({
    required String clubId,
    required String type,
    required String title,
    String? description,
    String? locationText,
    required DateTime startsAt,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    await _supabase.from('club_events').insert({
      'club_id': clubId,
      'created_by': uid,
      'type': type,
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (locationText != null && locationText.isNotEmpty)
        'location_text': locationText,
      'starts_at': startsAt.toUtc().toIso8601String(),
    });
  }

  /// 참석/불참 응답 (upsert).
  Future<void> respondEvent(String eventId, {required bool going}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw StateError('Not authenticated');
    await _supabase.from('club_event_attendees').upsert({
      'event_id': eventId,
      'user_id': uid,
      'status': going ? 'going' : 'not_going',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'event_id,user_id');
  }

  // ===== admin: clubs =====
  Future<List<Club>> pendingClubs() async {
    final rows = await _supabase
        .from('clubs')
        .select('*, club_members(role, status)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map(Club.fromJson).toList();
  }

  Future<void> approveClub(String clubId,
      {required bool approve, String? reason}) async {
    final res = await http.post(
      _uri('clubs-approve'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': approve ? 'approve' : 'reject',
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );
    _check(res);
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

  /// 관리자용: published 무관 전체 룰. embedding vector 는 제외(무거움).
  Future<List<RuleArticle>> adminListRules({String? sport}) async {
    var q = _supabase.from('rule_articles').select(
          'id, sport, category, title, body, order_idx, published, embedding_updated_at, updated_at',
        );
    if (sport != null) q = q.eq('sport', sport);
    final rows = await q.order('sport').order('category').order('order_idx');
    return (rows as List)
        .map((r) => RuleArticle.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> createRule(Map<String, dynamic> data) async {
    await _supabase.from('rule_articles').insert(data);
  }

  Future<void> updateRule(String id, Map<String, dynamic> data) async {
    await _supabase.from('rule_articles').update(data).eq('id', id);
  }

  Future<void> deleteRule(String id) async {
    await _supabase.from('rule_articles').delete().eq('id', id);
  }

  /// (sport, category) 내 다음 order_idx (max+1).
  Future<int> nextRuleOrderIdx(String sport, String category) async {
    final rows = await _supabase
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

  /// 즉시 재임베딩: embedding 무효화 후 embed-pending 호출.
  Future<void> recomputeRuleEmbedding(String id) async {
    await _supabase
        .from('rule_articles')
        .update({'embedding': null, 'embedding_updated_at': null}).eq('id', id);
    final res = await http.post(
      _uri('embed-pending'),
      headers: await _authHeaders(),
    );
    _check(res);
  }

  // ===== chat (SSE) =====

  /// SSE 스트리밍. 이벤트 라인을 yield 한다.
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
    String? activeSport,
    Map<String, String>? selectedEntity,
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
      if (activeSport != null) 'active_sport': activeSport,
      if (selectedEntity != null) 'selected_entity': selectedEntity,
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
  Future<void> saveDisplayName(String displayName) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');

    await _supabase.rpc('ensure_profile');
    await _supabase
        .from('users')
        .update({'display_name': displayName}).eq('id', userId);
  }

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

  // invokeCrawler 는 thin wrapper (crawl-tennis-*) 시절 헬퍼. PR #(이번) 에서 thin
  // wrapper 제거 + crawl-dispatch 로 일원화되어 사용처 없음. runCrawlSource(slug)
  // 사용.

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
      final row =
          await _supabase.from('crawl_sources').select().eq('id', id).single();
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
