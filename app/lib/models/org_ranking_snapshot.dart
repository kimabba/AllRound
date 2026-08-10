/// 부서 내 순위·포인트의 하루 스냅샷. 실명을 담지 않는다 — org_player_id 만.
/// 표시할 때는 org_rankings 의 현재 명단(이름)과 조인해 쓴다.
class OrgRankingSnapshot {
  const OrgRankingSnapshot({
    required this.orgCode,
    required this.divisionCode,
    required this.orgPlayerId,
    required this.capturedOn,
    required this.rank,
    required this.totalPoints,
  });

  final String orgCode;
  final String divisionCode;
  final String orgPlayerId;
  final DateTime capturedOn;
  final int rank;
  final int totalPoints;

  factory OrgRankingSnapshot.fromJson(Map<String, dynamic> j) {
    return OrgRankingSnapshot(
      orgCode: j['org_code'] as String,
      divisionCode: j['division_code'] as String,
      orgPlayerId: j['org_player_id'] as String,
      capturedOn: DateTime.parse(j['captured_on'] as String),
      rank: j['rank'] as int,
      totalPoints: j['total_points'] as int,
    );
  }
}
