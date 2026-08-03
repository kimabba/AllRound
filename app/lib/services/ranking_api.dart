import '../models/org_ranking.dart';
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

  /// 특정 협회에서 내 연결 상태(org_player_id, status) 전부.
  /// confirmed 는 랭킹 행 강조에, pending 은 "확인 중입니다" 표시에 쓴다.
  Future<List<Map<String, dynamic>>> myOrgPlayerLinks(String orgCode) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await supabase
        .from('org_player_links')
        .select('org_player_id, status')
        .eq('org_code', orgCode)
        .eq('user_id', userId);
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
}
