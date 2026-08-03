import 'dart:convert';

import '../models/admin.dart';
import '../models/crawl_source.dart';
import '../models/format_review.dart';
import '../models/org_ranking.dart';
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
          'format, source, source_url, poster_url, submitted_by, created_at',
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
    final res = await supabase.rpc(
      'tournaments_bulk_approve',
      params: {'p_ids': ids},
    );
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

  Future<void> approveClub(
    String clubId, {
    required bool approve,
    String? reason,
  }) async {
    await reviewClubs([clubId], approve: approve, reason: reason);
  }

  Future<int> reviewClubs(
    List<String> clubIds, {
    required bool approve,
    String? reason,
  }) async {
    if (clubIds.isEmpty) return 0;
    final trimmedReason = reason?.trim();
    if (!approve && (trimmedReason == null || trimmedReason.isEmpty)) {
      throw ArgumentError('rejection reason required');
    }
    var processed = 0;
    for (final clubId in clubIds) {
      final res = await httpPost(
        uri('clubs-approve'),
        headers: await authHeaders(),
        body: jsonEncode({
          'club_id': clubId,
          'action': approve ? 'approve' : 'reject',
          if (trimmedReason != null && trimmedReason.isNotEmpty)
            'reason': trimmedReason,
        }),
      );
      check(res);
      processed++;
    }
    return processed;
  }

  // ── 협회 랭킹 클레임 ──────────────────────────────────────────

  Future<List<RankingClaim>> pendingRankingClaims() =>
      _rankingClaimsByStatus('pending');

  Future<List<RankingClaim>> rejectedRankingClaims() =>
      _rankingClaimsByStatus('rejected');

  /// org_player_links 는 org_rankings 와 FK 로 묶여있지 않다(랭킹표는 크롤마다
  /// 갈아엎히므로 링크는 텍스트 org_player_id 로만 느슨하게 참조한다). 그래서
  /// 두 번 조회해 클라이언트에서 org_code/org_player_id 키로 합친다.
  Future<List<RankingClaim>> _rankingClaimsByStatus(String status) async {
    final links = await supabase
        .from('org_player_links')
        // org_player_links → users FK 가 두 개(user_id, decided_by) 라 힌트 없이
        // 임베드하면 PGRST201(관계 모호)로 죽는다. 이 레포의 기존 관례(club_api.dart
        // 의 users!author_id 등)를 따라 컬럼명으로 명시한다.
        .select(
          'org_code, org_player_id, user_id, claimed_at, users!user_id(name)',
        )
        .eq('status', status)
        .order('claimed_at');
    final linkRows = List<Map<String, dynamic>>.from(links as List);
    if (linkRows.isEmpty) return [];

    final orgCodes =
        linkRows.map((r) => r['org_code'] as String).toSet().toList();
    final playerIds =
        linkRows.map((r) => r['org_player_id'] as String).toSet().toList();
    final rankingRows = await supabase
        .from('org_rankings')
        .select(
          'org_code, org_player_id, division_code, rank, player_name, club_raw',
        )
        .inFilter('org_code', orgCodes)
        .inFilter('org_player_id', playerIds);

    final rankingByKey = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(rankingRows as List)) {
      rankingByKey.putIfAbsent(
        '${r['org_code']}/${r['org_player_id']}',
        () => r,
      );
    }

    return linkRows.map((link) {
      final key = '${link['org_code']}/${link['org_player_id']}';
      final ranking = rankingByKey[key];
      final userRow = link['users'] as Map<String, dynamic>?;
      // 경합 판정의 대조 축은 실명이다(협회 데이터도 실명) — 닉네임이면 관리자가
      // "같은 김평화인지" 비교할 수 없다. users.name 은 NOT NULL, 폴백 불필요.
      final claimantName = userRow?['name'] as String;
      return RankingClaim(
        orgCode: link['org_code'] as String,
        orgPlayerId: link['org_player_id'] as String,
        playerName: ranking?['player_name'] as String? ?? '(정보 없음)',
        divisionCode: ranking?['division_code'] as String? ?? '',
        rank: (ranking?['rank'] as num?)?.toInt() ?? 0,
        clubRaw: ranking?['club_raw'] as String?,
        claimantName: claimantName,
        claimantId: link['user_id'] as String,
        claimedAt: DateTime.parse(link['claimed_at'] as String),
      );
    }).toList();
  }

  /// 승인: status='confirmed' + decided_at/decided_by. 유니크 인덱스 위반(23505)은
  /// 정상 동작(경합에서 진 쪽)이라 여기서 삼키지 않고 그대로 던진다 — 호출자가
  /// PostgrestException.code 로 구분해 안내 문구를 고른다.
  Future<void> approveRankingClaim(RankingClaim claim) async {
    await _decideRankingClaim(claim, status: 'confirmed');
  }

  Future<void> rejectRankingClaim(RankingClaim claim) async {
    await _decideRankingClaim(claim, status: 'rejected');
  }

  Future<void> _decideRankingClaim(
    RankingClaim claim, {
    required String status,
  }) async {
    final adminId = supabase.auth.currentUser?.id;
    if (adminId == null) throw StateError('Not authenticated');
    await supabase
        .from('org_player_links')
        .update({
          'status': status,
          'decided_at': DateTime.now().toUtc().toIso8601String(),
          'decided_by': adminId,
        })
        .eq('org_code', claim.orgCode)
        .eq('org_player_id', claim.orgPlayerId)
        .eq('user_id', claim.claimantId);
  }

  /// 반려 취소 = 행 삭제. rejected 행이 남으면 유니크 제약이 재신청을 영구히 막는다.
  Future<void> undoRejectedRankingClaim(RankingClaim claim) async {
    await supabase
        .from('org_player_links')
        .delete()
        .eq('org_code', claim.orgCode)
        .eq('org_player_id', claim.orgPlayerId)
        .eq('user_id', claim.claimantId);
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
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(CrawlSource.fromJson).toList();
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
      final row = await supabase
          .from('crawl_sources')
          .select()
          .eq('id', id)
          .single();
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
    final res = await httpPost(
      uri('crawl-dispatch'),
      headers: await authHeaders(),
      body: jsonEncode({'slug': slug, 'force': force}),
    );
    check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── 요강 정형화 검수 ──────────────────────────────────────────

  Future<List<FormatReviewItem>> formatReviewQueue() async {
    final rows = await supabase
        .from('tournaments')
        .select(
          'id, title, source_url, format_source_hash, format_staged, '
          'format_flags',
        )
        .eq('format_status', 'needs_review')
        .order('updated_at');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(FormatReviewItem.fromJson).toList();
  }

  Future<bool> applyStaged(FormatReviewItem item) async {
    final res = await supabase.rpc(
      'format_apply_staged',
      params: {'p_tid': item.id, 'p_expected_source_hash': item.sourceHash},
    );
    return res == true;
  }

  Future<bool> rejectStaged(FormatReviewItem item, String reason) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('rejection reason required');
    }
    final res = await supabase.rpc(
      'format_reject_staged',
      params: {
        'p_tid': item.id,
        'p_expected_source_hash': item.sourceHash,
        'p_reason': trimmedReason,
      },
    );
    return res == true;
  }

  // ── Gemini 사용량 ─────────────────────────────────────────────

  /// [since] 이후 gemini_usage 를 kind·model 별로 집계 (요청수 + 토큰 합).
  /// 서버 RPC(gemini_usage_stats)가 admin 게이트 후 group-by 로 반환.
  Future<List<Map<String, dynamic>>> geminiUsageStats(DateTime since) async {
    final res = await supabase.rpc(
      'gemini_usage_stats',
      params: {'p_since': since.toUtc().toIso8601String()},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }
}
