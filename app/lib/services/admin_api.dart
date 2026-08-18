import 'dart:convert';

import '../models/admin.dart';
import '../models/crawl_source.dart';
import '../models/format_review.dart';
import '../models/org_ranking.dart';
import '../models/tournament.dart';
import '../utils/kst.dart';
import 'api_base.dart';

/// 어드민 전용: 심사 큐·크롤 소스·클럽 승인 API.
mixin AdminApi on ApiBase {
  // ── 대회 심사 큐 ──────────────────────────────────────────────

  /// 검수 대기(draft) 대회 목록. **시작일이 지난 크롤 대회는 제외한다.**
  ///
  /// 승인해봐야 소용이 없기 때문이다 — published 로 올려도 다음 크롤에서
  /// syncTournamentStatus 가 start_date 과거를 보고 곧바로 closed 로 되돌린다.
  /// 그런데 그 sync 는 published 만 다루므로 draft 는 영영 정리되지 않아,
  /// 거를 방법이 없으면 검수 큐에 지난 대회가 계속 쌓인다(2026-08-04: 14건 중 8건).
  ///
  /// **사람이 낸 대회(`user_submission`·제보자 있음)는 날짜와 무관하게 남긴다.**
  /// 크롤 대회는 날짜를 잘못 뽑아도 재크롤이 고쳐 주지만, 제보 대회는 다시
  /// 긁을 원본이 없다. 날짜 오타 하나로 큐에서 사라지면 그 사람은 자기 제보가
  /// 왜 처리되지 않는지 알 방법이 없다 — 반려도 승인도 못 받는다.
  Future<List<Map<String, dynamic>>> tournamentReviewQueue() async {
    // 오늘 시작하는 대회는 남긴다(당일 접수가 열려 있을 수 있다). start_date 는
    // date 컬럼이라 시각 없이 날짜만 비교한다.
    final cutoff = kstToday(DateTime.now());
    final rows = await supabase
        .from('tournaments')
        .select(
          'id, sport, title, organizer, description, start_date, end_date, '
          'application_deadline, region, location, eligible_grades, entry_fee, '
          'format, source, source_url, poster_url, submitted_by, created_at',
        )
        .eq('status', 'draft')
        .or(
          'source.eq.user_submission,'
          'submitted_by.not.is.null,'
          'start_date.gte.$cutoff',
        )
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
          'org_code, org_player_id, user_id, claimed_at, note, users!user_id(name)',
        )
        .eq('status', status)
        .order('claimed_at');
    final linkRows = List<Map<String, dynamic>>.from(links as List);
    if (linkRows.isEmpty) return [];

    final orgCodes =
        linkRows.map((r) => r['org_code'] as String).toSet().toList();
    final playerIds =
        linkRows.map((r) => r['org_player_id'] as String).toSet().toList();

    // 이 선수를 이미 확정으로 가진 사람. 있으면 이 신청은 이의신청이고, 관리자가
    // 기존 연결을 먼저 풀어야 승인할 수 있다(안 그러면 승인이 23505 로 죽는다).
    final confirmedRows = await supabase
        .from('org_player_links')
        .select('org_code, org_player_id, user_id, users!user_id(name)')
        .eq('status', 'confirmed')
        .inFilter('org_code', orgCodes)
        .inFilter('org_player_id', playerIds);
    final holderByKey = <String, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(confirmedRows as List)) {
      holderByKey['${r['org_code']}/${r['org_player_id']}'] = r;
    }

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
      final holder = holderByKey[key];
      final holderUser = holder?['users'] as Map<String, dynamic>?;
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
        note: link['note'] as String?,
        confirmedHolderName: holderUser?['name'] as String?,
        confirmedHolderId: holder?['user_id'] as String?,
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

  /// 이의신청 처리용 — 이 선수의 기존 확정 연결을 푼다(status='rejected').
  ///
  /// 삭제가 아니라 반려로 두는 이유: 누가 갖고 있었는지 기록이 남는다.
  /// (되돌리기는 자동이 아니다 — '반려됨'의 「취소(재검토)」는 행을 지울 뿐이고,
  /// 그 뒤 당사자가 다시 신청해야 한다.)
  /// 이걸 먼저 하지 않으면 이의신청 승인이
  /// org_player_links_confirmed_player_key(23505)에 걸린다.
  ///
  /// 다른 관리자가 먼저 처리해 보유자가 바뀌었을 수 있다. status 조건을 걸고
  /// 갱신 행 수를 확인해, 엉뚱한 행의 decided_* 만 덮어쓰고 성공으로 끝나는
  /// 경우를 막는다.
  Future<void> releaseConfirmedLink(RankingClaim claim) async {
    final holderId = claim.confirmedHolderId;
    if (holderId == null) {
      throw StateError('확정 연결이 없는 신청입니다');
    }
    final adminId = supabase.auth.currentUser?.id;
    if (adminId == null) throw StateError('Not authenticated');
    final updated = await supabase
        .from('org_player_links')
        .update({
          'status': 'rejected',
          'decided_at': DateTime.now().toUtc().toIso8601String(),
          'decided_by': adminId,
        })
        .eq('org_code', claim.orgCode)
        .eq('org_player_id', claim.orgPlayerId)
        .eq('user_id', holderId)
        .eq('status', 'confirmed')
        .select('user_id');
    if ((updated as List).isEmpty) {
      throw StateError('이미 다른 관리자가 처리했습니다. 새로고침 후 다시 확인하세요');
    }
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

  /// [month] 이 속한 달의 일별 Gemini 사용량 집계(요청수 + 토큰 합, 날짜별).
  /// 서버 RPC(gemini_usage_daily_stats)가 admin 게이트 후 KST 기준 날짜로 group-by.
  /// [month] 를 안 주면 서버가 KST 기준 이번 달로 판정한다 — 기기 로컬 시간대가
  /// KST 와 다르면(예: UTC) 클라이언트가 계산한 "이번 달"이 월 경계 근처에서
  /// 서버 판정과 어긋날 수 있어, 굳이 계산해 보내지 않는다.
  Future<List<Map<String, dynamic>>> geminiUsageDailyStats([DateTime? month]) async {
    final p = month == null
        ? null
        : '${month.year.toString().padLeft(4, '0')}-'
              '${month.month.toString().padLeft(2, '0')}-01';
    final res = await supabase.rpc(
      'gemini_usage_daily_stats',
      params: {'p_month': p},
    );
    return List<Map<String, dynamic>>.from(res as List);
  }
}
