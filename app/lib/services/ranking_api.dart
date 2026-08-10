import '../models/org_ranking.dart';
import '../models/player_result.dart';
import 'api_base.dart';

/// 협회 랭킹 조회 + 본인 계정 연결(클레임). 관리자 승인 큐는 AdminApi 를 쓴다.
mixin RankingApi on ApiBase {
  /// 협회·부서 하나의 순위표. rank 오름차순(협회 공표 그대로, 앱이 재계산하지 않음).
  Future<List<OrgRankingRow>> orgRankings({
    required String orgCode,
    required String divisionCode,
  }) async {
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', orgCode)
        .eq('division_code', divisionCode)
        .order('rank');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
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
  Future<void> claimRanking(OrgRankingRow candidate) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Not authenticated');
    final orgPlayerId = candidate.orgPlayerId;
    if (orgPlayerId == null) {
      throw ArgumentError('candidate.orgPlayerId is required to claim');
    }
    await supabase.from('org_player_links').insert({
      'org_code': candidate.orgCode,
      'org_player_id': orgPlayerId,
      'user_id': userId,
      'status': 'pending',
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

  /// 내 협회 전적 전량(최신 대회순).
  ///
  /// org_code/org_player_id 로 명시 필터한다 — RLS 에 기대면 관리자 계정은
  /// `org_player_results_admin_all` 정책 때문에 전체 선수 전적을 받는다.
  /// (RLS 는 그대로 방어선이고, 이건 앱이 "내 것만" 의도를 명시하는 것.)
  Future<List<PlayerResult>> myPlayerResults() async {
    final link = await myConfirmedLink();
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
  Future<Map<String, dynamic>?> myConfirmedLink() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await supabase
        .from('org_player_links')
        .select('org_code, org_player_id')
        .eq('user_id', userId)
        .eq('status', 'confirmed')
        .order('org_code')
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
  /// 한 선수가 여러 부서 랭킹에 오를 수 있어 목록으로 돌려준다.
  Future<List<OrgRankingRow>> myCurrentRankings() async {
    final link = await myConfirmedLink();
    if (link == null) return const [];
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', link['org_code'] as String)
        .eq('org_player_id', link['org_player_id'] as String)
        .order('division_code');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
  }
}
