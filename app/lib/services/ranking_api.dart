import 'dart:convert';

import '../models/org_ranking.dart';
import '../models/org_ranking_snapshot.dart';
import '../models/player_result.dart';
import 'api_base.dart';

/// 협회 랭킹 조회 + 본인 계정 연결(클레임). 관리자 승인 큐는 AdminApi 를 쓴다.
mixin RankingApi on ApiBase {
  /// 협회·부서 하나의 순위표. rank 오름차순(협회 공표 그대로, 앱이 재계산하지 않음).
  ///
  /// supabase-dart 의 order() 는 SQL/postgrest-js 와 반대로 ascending 기본값이
  /// false 다 — 명시하지 않으면 조용히 내림차순(꼴찌부터)이 된다.
  Future<List<OrgRankingRow>> orgRankings({
    required String orgCode,
    required String divisionCode,
  }) async {
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', orgCode)
        .eq('division_code', divisionCode)
        .order('rank', ascending: true);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
  }

  /// 랭킹표에서 선택한 선수의 협회 공표 대회 이력.
  ///
  /// 클라이언트가 협회 원본을 직접 긁지 않는다. Edge Function 이 현재 랭킹 선수인지
  /// 검증하고 호출 제한·24시간 캐시를 적용한 뒤 정규화된 결과만 반환한다.
  Future<PlayerHistory> playerHistory(OrgRankingRow player) async {
    final playerId = player.orgPlayerId;
    if (playerId == null) {
      throw ArgumentError('player.orgPlayerId is required for history');
    }
    final response = await httpGet(
      uri('ranking-player-history', {
        'org': player.orgCode,
        'player_id': playerId,
      }),
      headers: await authHeaders(),
    );
    check(response);

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid player history response');
    }
    final rawResults = decoded['results'];
    final rawFetchedAt = decoded['fetched_at'];
    final rawComplete = decoded['is_complete'];
    final rawCached = decoded['cached'];
    if (rawResults is! List ||
        rawFetchedAt is! String ||
        rawComplete is! bool ||
        rawCached is! bool) {
      throw const FormatException('Invalid player history payload');
    }

    final results = <PlayerResult>[];
    for (final item in rawResults) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid player history row');
      }
      results.add(PlayerResult.fromJson(item));
    }
    return PlayerHistory(
      results: results,
      fetchedAt: DateTime.parse(rawFetchedAt),
      isComplete: rawComplete,
      wasCached: rawCached,
    );
  }

  /// 내 이름·소속 협회·등록 부서와 일치하는 랭킹 후보. 이미 신청/확정된 건 RPC 가 제외한다.
  Future<List<OrgRankingRow>> myRankingCandidates() async {
    final rows = await supabase.rpc('my_ranking_candidates');
    return List<Map<String, dynamic>>.from(
      rows as List,
    ).map(OrgRankingRow.fromJson).toList();
  }

  /// 특정 협회에서 내가 볼 수 있는 연결 전부 — 내 것(모든 status) + 남의 confirmed.
  /// RLS(`org_player_links_read`)가 딱 그만큼만 주므로 필터 없이 그대로 받는다.
  ///
  /// 내 confirmed 는 랭킹 행 강조에, 내 pending 은 "확인 중" 표시에,
  /// 남의 confirmed 는 이미 주인이 있는 행의 신청 버튼을 숨기는 데 쓴다.
  Future<List<Map<String, dynamic>>> orgPlayerLinks(String orgCode) async {
    final rows = await supabase
        .from('org_player_links')
        .select('org_player_id, status, user_id')
        .eq('org_code', orgCode);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// 랭킹 후보 신청 — pending 클레임 생성. 관리자 승인 전까지 "확인 중"이다.
  ///
  /// [note] 는 이의신청(이미 남과 확정된 선수를 두고 다투는 경우)에서 쓴다.
  /// 경합하는 두 사람은 정책상 이름이 반드시 같아서, 관리자가 가릴 재료가
  /// 이것뿐이다. 승인·반려되면 DB 트리거가 지운다(확정 행은 전체 공개다).
  Future<void> claimRanking(OrgRankingRow candidate, {String? note}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final orgPlayerId = candidate.orgPlayerId;
    if (orgPlayerId == null) {
      throw ArgumentError('candidate.orgPlayerId is required to claim');
    }
    final trimmed = note?.trim();
    await supabase.from('org_player_links').insert({
      'org_code': candidate.orgCode,
      'org_player_id': orgPlayerId,
      'user_id': userId,
      'status': 'pending',
      // 공백만 남으면 CHECK(org_player_links_note_len)에 걸린다 — null 로 보낸다.
      if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
    });
  }

  /// 랭킹 표의 아무 선수나 눌렀을 때 보는 전적(최신 대회순).
  ///
  /// org_player_results_read RLS(2026-08-10)로 로그인 사용자 전체에게 열려
  /// 있다 — org_rankings 표 자체가 이미 공개하는 것과 같은 데이터다. 다만
  /// 크롤러가 아직 "본인 연결 승인자"만 전적을 적재하므로, 연결 안 된 선수는
  /// 빈 목록이 정상이다(전적이 없는 게 아니라 아직 안 모은 것).
  Future<List<PlayerResult>> playerResults({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    final rows = await supabase
        .from('org_player_results')
        .select()
        .eq('org_code', orgCode)
        .eq('org_player_id', orgPlayerId)
        .order('played_on', ascending: false);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(PlayerResult.fromJson).toList();
  }

  /// 순위 추이(부서 하나). org_ranking_snapshots_read RLS(2026-08-10)로
  /// 로그인 사용자 전체에게 열려 있다. 전 선수가 매일 자동 적재되므로
  /// (연결 여부 무관) 대부분의 선수가 이 데이터를 갖는다.
  Future<List<OrgRankingSnapshot>> playerRankingHistory({
    required String orgCode,
    required String divisionCode,
    required String orgPlayerId,
  }) async {
    final rows = await supabase
        .from('org_ranking_snapshots')
        .select()
        .eq('org_code', orgCode)
        .eq('division_code', divisionCode)
        .eq('org_player_id', orgPlayerId)
        .order('captured_on', ascending: true);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingSnapshot.fromJson).toList();
  }

  /// 내 협회 전적 전량(최신 대회순).
  ///
  /// org_code/org_player_id 로 명시 필터한다 — RLS 에 기대면 관리자 계정은
  /// `org_player_results_admin_all` 정책 때문에 전체 선수 전적을 받는다.
  /// (RLS 는 그대로 방어선이고, 이건 앱이 "내 것만" 의도를 명시하는 것.)
  ///
  /// [orgCode] 를 주면 그 협회의 연결만 본다 — [myConfirmedLink] 참조.
  Future<List<PlayerResult>> myPlayerResults({String? orgCode}) async {
    final link = await myConfirmedLink(orgCode: orgCode);
    if (link == null) return const [];
    final rows = await supabase
        .from('org_player_results')
        .select()
        .eq('org_code', link['org_code'] as String)
        .eq('org_player_id', link['org_player_id'] as String)
        .order('played_on', ascending: false);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(PlayerResult.fromJson).toList();
  }

  /// 내 확정 연결 1건(없으면 null). 기록 화면이 연결 여부로 갈리므로 필요하다.
  ///
  /// DB 제약상 한 유저가 광주·전남 두 협회에 동시에 confirmed 될 수 있어
  /// org_code 로 정렬해 최소한 결과가 안정적이게 한다(어느 쪽이 나오든 매번 같다).
  ///
  /// [orgCode] 를 주면 그 협회로 좁혀 찾는다 — 랭킹 화면이 지금 보는 협회의
  /// 카드를 탭해 내 기록으로 들어올 때, 광주+전남 동시 confirmed 사용자가
  /// 항상 정렬 1순위(광주)만 보게 되는 걸 막는다. 기본값 null 은 기존 동작(정렬
  /// 1순위) 그대로다 — 기존 호출부는 전부 무수정으로 컴파일된다.
  Future<Map<String, dynamic>?> myConfirmedLink({String? orgCode}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    var query = supabase
        .from('org_player_links')
        .select('org_code, org_player_id')
        .eq('user_id', userId)
        .eq('status', 'confirmed');
    if (orgCode != null) {
      query = query.eq('org_code', orgCode);
    }
    final rows = await query.order('org_code').limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// 부서 순위표에서 [rank] 위 한 줄(없으면 null). "TOP 10 까지 남은 점수"처럼
  /// 커트라인 한 줄만 필요할 때 쓴다 — orgRankings 를 쓰면 홈 화면이 열릴 때마다
  /// 부서 순위표 전체(수백 행)를 받게 된다.
  Future<OrgRankingRow?> divisionRankRow({
    required String orgCode,
    required String divisionCode,
    required int rank,
  }) async {
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', orgCode)
        .eq('division_code', divisionCode)
        .eq('rank', rank)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : OrgRankingRow.fromJson(list.first);
  }

  /// 한 협회 안에서 특정 선수의 현재 순위(오른 부서 전부).
  ///
  /// 랭킹 화면의 "내 기록 요약"이 쓴다 — 지금 보는 부서와 내가 연결된 부서가
  /// 달라도 내 순위를 보여줘야 해서, 부서 필터 없이 협회+선수로 조회한다.
  /// 대표 부서 선정은 호출부가 topDivisionRanking 으로 한다.
  ///
  /// order 는 ascending 을 명시하지 않는다(= 내림차순, 파일 상단 주석 참조) —
  /// myCurrentRankings 가 위임하는데, myRankingHistoryProvider 가 결과의
  /// first 에 의존하고 있어 순서를 바꾸면 내 기록 화면의 추이 부서가 바뀐다.
  Future<List<OrgRankingRow>> playerRankings({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', orgCode)
        .eq('org_player_id', orgPlayerId)
        .order('division_code');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
  }

  /// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
  /// 한 선수가 여러 부서 랭킹에 오를 수 있어 목록으로 돌려준다.
  ///
  /// [orgCode] 를 주면 그 협회의 연결만 본다 — [myConfirmedLink] 참조.
  Future<List<OrgRankingRow>> myCurrentRankings({String? orgCode}) async {
    final link = await myConfirmedLink(orgCode: orgCode);
    if (link == null) return const [];
    return playerRankings(
      orgCode: link['org_code'] as String,
      orgPlayerId: link['org_player_id'] as String,
    );
  }
}
