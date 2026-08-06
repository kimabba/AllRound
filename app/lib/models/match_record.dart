class MatchEntry {
  final String id;
  final String userId;
  final String tournamentId;
  final String? tournamentTitle;
  final String division;
  final String? partnerId;
  final String? partnerName;
  final String? teamName;
  final String? finalRound;
  final int pointsEarned;
  final String source;
  final DateTime createdAt;
  final List<MatchRound> rounds;

  const MatchEntry({
    required this.id,
    required this.userId,
    required this.tournamentId,
    this.tournamentTitle,
    required this.division,
    this.partnerId,
    this.partnerName,
    this.teamName,
    this.finalRound,
    this.pointsEarned = 0,
    this.source = 'manual',
    required this.createdAt,
    this.rounds = const [],
  });

  factory MatchEntry.fromJson(Map<String, dynamic> j) {
    final tournament = j['tournaments'] as Map<String, dynamic>?;
    final roundsList = j['match_rounds'] as List?;
    return MatchEntry(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      tournamentId: j['tournament_id'] as String,
      tournamentTitle: tournament?['title'] as String?,
      division: j['division'] as String,
      partnerId: j['partner_id'] as String?,
      partnerName: j['partner_name'] as String?,
      teamName: j['team_name'] as String?,
      finalRound: j['final_round'] as String?,
      pointsEarned: (j['points_earned'] as int?) ?? 0,
      source: (j['source'] as String?) ?? 'manual',
      createdAt: DateTime.parse(j['created_at'] as String),
      rounds: roundsList
              ?.map((r) =>
                  MatchRound.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  String get finalRoundLabel => switch (finalRound) {
        'winner' => '우승',
        'runner_up' => '준우승',
        'semi_final' => '4강',
        'quarter_final' => '8강',
        'round_of_16' => '16강',
        'round_of_32' => '32강',
        'first_round' => '1회전',
        _ => finalRound ?? '-',
      };
}

class MatchRound {
  final String id;
  final String entryId;
  final String round;
  final String? opponent1Id;
  final String? opponent1Name;
  final String? opponent2Id;
  final String? opponent2Name;
  final String? score;
  final String result;
  final DateTime? playedAt;

  const MatchRound({
    required this.id,
    required this.entryId,
    required this.round,
    this.opponent1Id,
    this.opponent1Name,
    this.opponent2Id,
    this.opponent2Name,
    this.score,
    required this.result,
    this.playedAt,
  });

  factory MatchRound.fromJson(Map<String, dynamic> j) => MatchRound(
        id: j['id'] as String,
        entryId: j['entry_id'] as String,
        round: j['round'] as String,
        opponent1Id: j['opponent_1_id'] as String?,
        opponent1Name: j['opponent_1_name'] as String?,
        opponent2Id: j['opponent_2_id'] as String?,
        opponent2Name: j['opponent_2_name'] as String?,
        score: j['score'] as String?,
        result: j['result'] as String,
        playedAt: j['played_at'] != null
            ? DateTime.parse(j['played_at'] as String)
            : null,
      );

  bool get isWin => result == 'win';

  String get opponentDisplay {
    final names = [opponent1Name, opponent2Name]
        .whereType<String>()
        .where((n) => n.isNotEmpty);
    return names.isEmpty ? '상대 미입력' : names.join(' / ');
  }
}
