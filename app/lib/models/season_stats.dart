import 'org_ranking_snapshot.dart';
import 'player_result.dart';

/// 대회 참가·우승·최고 순위·전적 분포를 하나로 묶은 "이 시즌 기록" 요약.
/// org_player_results/org_ranking_snapshots 에서 파생된 사실만 담는다 —
/// 앱이 새 점수·레벨을 만들지 않는다.
class SeasonStats {
  const SeasonStats({
    required this.tournamentsThisYear,
    required this.careerWins,
    required this.seasonBestRank,
    required this.resultDistribution,
  });

  final int tournamentsThisYear;
  final int careerWins;
  final int? seasonBestRank;

  /// key: result_round(1=우승, 2=준우승, 4=4강 …). null 은 정규화 실패(원문만 있음).
  final Map<int?, int> resultDistribution;

  factory SeasonStats.compute({
    required List<PlayerResult> results,
    required List<OrgRankingSnapshot> snapshots,
    required int currentYear,
  }) {
    final tournamentsThisYear =
        results.where((r) => r.playedOn.year == currentYear).length;
    final careerWins = results.where((r) => r.resultRound == 1).length;

    int? seasonBestRank;
    for (final s in snapshots) {
      if (seasonBestRank == null || s.rank < seasonBestRank) {
        seasonBestRank = s.rank;
      }
    }

    final distribution = <int?, int>{};
    for (final r in results) {
      distribution.update(r.resultRound, (v) => v + 1, ifAbsent: () => 1);
    }

    return SeasonStats(
      tournamentsThisYear: tournamentsThisYear,
      careerWins: careerWins,
      seasonBestRank: seasonBestRank,
      resultDistribution: distribution,
    );
  }
}

/// 전적 분포 칩에 쓰는 라벨. [PlayerResult.resultLabel] 과 달리 원문(resultRaw)이
/// 없다 — 집계값이라 특정 대회 하나를 가리키지 않는다.
String seasonDistributionLabel(int? resultRound) => switch (resultRound) {
      1 => '우승',
      2 => '준우승',
      final int n => '$n강',
      null => '기타',
    };
