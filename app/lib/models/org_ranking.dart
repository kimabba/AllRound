/// 협회 랭킹 한 행. 협회가 공표한 값 그대로이며 앱이 계산한 값이 아니다.
class OrgRankingRow {
  const OrgRankingRow({
    required this.orgCode,
    required this.divisionCode,
    required this.rank,
    required this.playerName,
    required this.rankPoints,
    required this.totalPoints,
    this.orgPlayerId,
    this.clubRaw,
  });

  final String orgCode;
  final String divisionCode;
  final int rank;
  final String playerName;
  final int rankPoints;
  final int totalPoints;
  final String? orgPlayerId;
  final String? clubRaw;

  factory OrgRankingRow.fromJson(Map<String, dynamic> j) {
    return OrgRankingRow(
      orgCode: j['org_code'] as String,
      divisionCode: j['division_code'] as String,
      rank: j['rank'] as int,
      playerName: j['player_name'] as String,
      rankPoints: j['rank_points'] as int,
      totalPoints: j['total_points'] as int,
      orgPlayerId: j['org_player_id'] as String?,
      clubRaw: j['club_raw'] as String?,
    );
  }
}

/// 협회 선수에 대한 계정 연결 신청 1건.
class RankingClaim {
  const RankingClaim({
    required this.orgCode,
    required this.orgPlayerId,
    required this.playerName,
    required this.divisionCode,
    required this.rank,
    required this.claimantName,
    required this.claimantId,
    required this.claimedAt,
    this.clubRaw,
  });

  final String orgCode;
  final String orgPlayerId;
  final String playerName;
  final String divisionCode;
  final int rank;
  final String claimantName;
  final String claimantId;
  final DateTime claimedAt;
  final String? clubRaw;
}

/// 같은 협회 선수를 놓고 겨루는 신청들의 묶음.
class ClaimGroup {
  const ClaimGroup({
    required this.orgCode,
    required this.orgPlayerId,
    required this.playerName,
    required this.divisionCode,
    required this.rank,
    required this.claimants,
    this.clubRaw,
  });

  final String orgCode;
  final String orgPlayerId;
  final String playerName;
  final String divisionCode;
  final int rank;
  final List<RankingClaim> claimants;
  final String? clubRaw;

  /// 한 선수에 신청이 둘 이상 — 관리자가 골라야 한다.
  bool get isContested => claimants.length > 1;
}
