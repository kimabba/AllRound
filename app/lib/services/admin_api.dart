import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin.dart';
import '../models/crawl_source.dart';
import '../models/tournament.dart';
import 'api_base.dart';

/// 어드민 전용: 심사 큐·크롤 소스·클럽 승인 API.
mixin AdminApi on ApiBase {
  // ── 대회 심사 큐 ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> tournamentReviewQueue() async {
    final rows = await supabase
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

  Future<int> bulkApproveTournaments(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final res =
        await supabase.rpc('tournaments_bulk_approve', params: {'p_ids': ids});
    return (res as num).toInt();
  }

  Future<int> bulkRejectTournaments(List<String> ids, String reason) async {
    if (ids.isEmpty) return 0;
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('rejection reason required');
    }
    final res = await supabase.rpc(
      'tournaments_bulk_reject',
      params: {'p_ids': ids, 'p_reason': trimmed},
    );
    return (res as num).toInt();
  }

  // ── 클럽 승인 ─────────────────────────────────────────────────

  Future<List<Club>> pendingClubs() async {
    final rows = await supabase
        .from('clubs')
        .select('*, club_members(role, status)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map(Club.fromJson).toList();
  }

  Future<void> approveClub(String clubId,
      {required bool approve, String? reason}) async {
    final res = await http.post(
      uri('clubs-approve'),
      headers: await authHeaders(),
      body: jsonEncode({
        'club_id': clubId,
        'action': approve ? 'approve' : 'reject',
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );
    check(res);
  }

  // ── 크롤 소스 ─────────────────────────────────────────────────

  Future<List<CrawlAuditLog>> crawlAuditLogs({int limit = 30}) async {
    final rows = await supabase
        .from('crawl_audit')
        .select()
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map((r) => CrawlAuditLog.fromJson(r)).toList();
  }

  Future<List<CrawlSource>> crawlSources() async {
    final rows = await supabase
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
    final row = await supabase
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
      final row =
          await supabase.from('crawl_sources').select().eq('id', id).single();
      return CrawlSource.fromJson(row);
    }
    final row = await supabase
        .from('crawl_sources')
        .update(patch)
        .eq('id', id)
        .select()
        .single();
    return CrawlSource.fromJson(row);
  }

  Future<void> deleteCrawlSource(String id) async {
    await supabase.from('crawl_sources').delete().eq('id', id);
  }

  Future<CrawlSource> toggleCrawlSourceEnabled(String id, bool enabled) async {
    return updateCrawlSource(id, enabled: enabled);
  }

  Future<Map<String, dynamic>> runCrawlSource(
    String slug, {
    bool force = true,
  }) async {
    final res = await http.post(
      uri('crawl-dispatch'),
      headers: await authHeaders(),
      body: jsonEncode({'slug': slug, 'force': force}),
    );
    check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
