import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/models/season_stats.dart';

PlayerResult _r({required String on, int? round, int points = 0}) =>
    PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': 'x',
      'played_on': on,
      'result_raw': round?.toString() ?? '예선탈락',
      'result_round': round,
      'points': points,
    });

OrgRankingSnapshot _s({required String on, required int rank}) =>
    OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'a',
      'captured_on': on,
      'rank': rank,
      'total_points': 1000,
    });

void main() {
  group('SeasonStats.compute', () {
    test('빈 입력이면 전부 0/없음이다', () {
      final stats = SeasonStats.compute(
        results: const [],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.tournamentsThisYear, 0);
      expect(stats.careerWins, 0);
      expect(stats.allTimeBestRank, isNull);
      expect(stats.resultDistribution, isEmpty);
    });

    test('올해 참가만 세고 작년 참가는 제외한다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: 4),
          _r(on: '2025-12-31', round: 4),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.tournamentsThisYear, 1);
    });

    test('resultRound가 1인 행만 우승으로 세고, 연도와 무관하게 누적한다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: 1),
          _r(on: '2025-01-01', round: 1),
          _r(on: '2026-02-01', round: 2),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.careerWins, 2);
    });

    test('가장 낮은(=가장 좋은) 순위를 역대 최고로 뽑는다', () {
      final stats = SeasonStats.compute(
        results: const [],
        snapshots: [
          _s(on: '2026-08-04', rank: 12),
          _s(on: '2026-08-05', rank: 3),
          _s(on: '2026-08-06', rank: 7),
        ],
        currentYear: 2026,
      );
      expect(stats.allTimeBestRank, 3);
    });

    test('resultRound가 null인 행은 null 키로 묶인다', () {
      final stats = SeasonStats.compute(
        results: [
          _r(on: '2026-01-01', round: null),
          _r(on: '2026-01-02', round: null),
          _r(on: '2026-01-03', round: 1),
        ],
        snapshots: const [],
        currentYear: 2026,
      );
      expect(stats.resultDistribution[null], 2);
      expect(stats.resultDistribution[1], 1);
    });
  });

  group('seasonDistributionLabel', () {
    test('1=우승, 2=준우승, 그 외 정수=N강, null=기타', () {
      expect(seasonDistributionLabel(1), '우승');
      expect(seasonDistributionLabel(2), '준우승');
      expect(seasonDistributionLabel(4), '4강');
      expect(seasonDistributionLabel(null), '기타');
    });
  });
}
