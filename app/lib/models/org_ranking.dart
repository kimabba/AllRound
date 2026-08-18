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
    this.fetchedAt,
  });

  final String orgCode;
  final String divisionCode;
  final int rank;
  final String playerName;
  final int rankPoints;
  final int totalPoints;
  final String? orgPlayerId;
  final String? clubRaw;
  // my_ranking_candidates() RPC 는 이 컬럼을 안 돌려준다(후보 카드에는 기준일이
  // 필요 없다) — null 허용.
  final DateTime? fetchedAt;

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
      fetchedAt: j['fetched_at'] == null
          ? null
          : DateTime.parse(j['fetched_at'] as String),
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
    this.note,
    this.confirmedHolderName,
    this.confirmedHolderId,
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

  /// 신청자가 적은 사유. 이의신청에서만 채워진다 — 경합하는 두 사람은 정책상
  /// 이름이 같아서(users.name = player_name) 관리자가 가릴 재료가 이것뿐이다.
  /// 승인·반려되면 DB 트리거가 지운다.
  final String? note;

  /// 이 선수를 이미 확정으로 갖고 있는 사람. null 이면 빈 자리다.
  /// 값이 있으면 이 신청은 이의신청이고, 먼저 이 연결을 풀어야 승인할 수 있다
  /// (org_player_links_confirmed_player_key 가 승인 시점에 23505 를 낸다).
  final String? confirmedHolderName;
  final String? confirmedHolderId;
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
    this.confirmedHolderName,
    this.confirmedHolderId,
  });

  final String orgCode;
  final String orgPlayerId;
  final String playerName;
  final String divisionCode;
  final int rank;
  final List<RankingClaim> claimants;
  final String? clubRaw;

  /// 이 선수를 이미 확정으로 갖고 있는 사람(있다면).
  final String? confirmedHolderName;
  final String? confirmedHolderId;

  /// 한 선수에 신청이 둘 이상 — 관리자가 골라야 한다.
  bool get isContested => claimants.length > 1;

  /// 이미 주인이 있는 선수에 들어온 신청 = 이의신청.
  /// 기존 연결을 풀기 전에는 승인이 DB 에서 막힌다.
  bool get isDisputed => confirmedHolderId != null;
}
