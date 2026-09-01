/// 협회가 공표한 개인 대회 전적 1건. 앱이 계산한 값이 아니다.
///
/// `resultRound` 는 그 대회 진출 라운드(1=우승, 2=준우승, 4=4강)이지
/// 부서 내 랭킹 순위가 아니다. 협회 표기를 못 읽으면 null 이고,
/// 그때는 `resultRaw` 원문을 그대로 보여준다.
class PlayerResult {
  const PlayerResult({
    required this.orgCode,
    required this.orgPlayerId,
    required this.tournamentName,
    required this.playedOn,
    required this.resultRaw,
    required this.points,
    this.eventRaw,
    this.resultRound,
  });

  final String orgCode;
  final String orgPlayerId;
  final String tournamentName;
  final DateTime playedOn;
  final String resultRaw;
  final int points;
  final String? eventRaw;
  final int? resultRound;

  factory PlayerResult.fromJson(Map<String, dynamic> j) {
    return PlayerResult(
      orgCode: j['org_code'] as String,
      orgPlayerId: j['org_player_id'] as String,
      tournamentName: j['tournament_name'] as String,
      playedOn: DateTime.parse(j['played_on'] as String),
      resultRaw: j['result_raw'] as String,
      points: (j['points'] as int?) ?? 0,
      eventRaw: j['event_raw'] as String?,
      resultRound: j['result_round'] as int?,
    );
  }

  /// 화면 표기. 정규화가 안 된 행은 협회 원문을 그대로 쓴다 — 빈칸이나 추측값 금지.
  String get resultLabel => switch (resultRound) {
        1 => '우승',
        2 => '준우승',
        final int n => '$n강',
        null => resultRaw,
      };

  bool get isWin => resultRound == 1;
}

/// 랭킹표에서 선택한 선수의 협회 공표 이력 묶음.
class PlayerHistory {
  const PlayerHistory({
    required this.results,
    required this.fetchedAt,
    required this.isComplete,
    required this.wasCached,
  });

  final List<PlayerResult> results;
  final DateTime fetchedAt;
  final bool isComplete;
  final bool wasCached;
}
