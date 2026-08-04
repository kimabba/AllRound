import 'package:allround/models/tournament.dart';
import 'package:allround/screens/tournaments/tournaments_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 최소 필드만 채운 대회. 레인 배치는 startDate/endDate만 사용한다.
Tournament _t({required DateTime start, DateTime? end}) => Tournament(
      id: 'x',
      sport: 'tennis',
      title: 't',
      startDate: start,
      endDate: end,
      eligibleGrades: const [],
      status: 'open',
    );

void main() {
  group('laneLayoutForWeek', () {
    test('주 중간에 걸친 구간: 레인0에 시작/중간/끝 모서리', () {
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final layout = laneLayoutForWeek(
        week,
        [_t(start: DateTime(2026, 7, 15), end: DateTime(2026, 7, 19))],
      );
      // 13, 14: 레인 없음
      expect(layout.laneGrid[0][0], isNull);
      expect(layout.laneGrid[1][0], isNull);
      // 15: 구간 시작
      expect(layout.laneGrid[2][0]!.isBandStart, isTrue);
      expect(layout.laneGrid[2][0]!.isBandEnd, isFalse);
      // 16~18: 중간 (양쪽 각짐)
      for (final i in [3, 4, 5]) {
        expect(layout.laneGrid[i][0], isNotNull);
        expect(layout.laneGrid[i][0]!.isBandStart, isFalse);
        expect(layout.laneGrid[i][0]!.isBandEnd, isFalse);
      }
      // 19: Row 마지막 → 끝
      expect(layout.laneGrid[6][0]!.isBandStart, isFalse);
      expect(layout.laneGrid[6][0]!.isBandEnd, isTrue);
      expect(layout.overflowCounts, everyElement(0));
    });

    test('주간 경계: 토요일 칸은 시작이자 끝(Row 마지막 + 왼쪽 없음)', () {
      // 대회 7/18(토)~7/20(월). 첫 주 마지막 칸이 7/18.
      final tour = [
        _t(start: DateTime(2026, 7, 18), end: DateTime(2026, 7, 20))
      ];
      final firstWeek = [
        for (var d = 12; d <= 18; d++) DateTime(2026, 7, d),
      ];
      final firstLayout = laneLayoutForWeek(firstWeek, tour);
      expect(firstLayout.laneGrid[6][0]!.isBandStart, isTrue); // 왼쪽(7/17) 없음
      expect(firstLayout.laneGrid[6][0]!.isBandEnd, isTrue); // Row 마지막

      final nextWeek = [
        for (var d = 19; d <= 25; d++) DateTime(2026, 7, d),
      ];
      final nextLayout = laneLayoutForWeek(nextWeek, tour);
      expect(nextLayout.laneGrid[0][0]!.isBandStart, isTrue); // 7/19 Row 처음
      expect(nextLayout.laneGrid[0][0]!.isBandEnd, isFalse);
      expect(nextLayout.laneGrid[1][0]!.isBandStart, isFalse); // 7/20 끝
      expect(nextLayout.laneGrid[1][0]!.isBandEnd, isTrue);
      expect(nextLayout.laneGrid[2][0], isNull); // 7/21
    });

    test('null 셀 경계: 왼쪽 null이면 시작 모서리', () {
      // 6/30~7/2 대회, 월 첫 주 [null, null, 7/1, 7/2, ...]
      final tour = [
        _t(start: DateTime(2026, 6, 30), end: DateTime(2026, 7, 2))
      ];
      final week = <DateTime?>[
        null,
        null,
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 2),
        DateTime(2026, 7, 3),
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 5),
      ];
      final layout = laneLayoutForWeek(week, tour);
      expect(layout.laneGrid[2][0]!.isBandStart, isTrue); // 7/1, 왼쪽 null
      expect(layout.laneGrid[3][0]!.isBandEnd, isTrue); // 7/2 끝
      expect(layout.laneGrid[4][0], isNull); // 7/3
    });

    test('겹치는 대회는 서로 다른 레인에 배치된다', () {
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final layout = laneLayoutForWeek(week, [
        _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 16)),
        _t(start: DateTime(2026, 7, 15), end: DateTime(2026, 7, 17)),
      ]);
      // 13: 첫 대회만, 레인0
      expect(layout.laneGrid[0][0], isNotNull);
      expect(layout.laneGrid[0][1], isNull);
      // 15~16: 겹치는 구간, 레인0+레인1 둘 다 찬다
      expect(layout.laneGrid[2][0], isNotNull); // 15, 레인0
      expect(layout.laneGrid[2][1], isNotNull); // 15, 레인1
      expect(layout.laneGrid[3][0], isNotNull); // 16, 레인0
      expect(layout.laneGrid[3][1], isNotNull); // 16, 레인1
      // 17: 두번째 대회만. 레인은 구간이 겹칠 때 배정된 레인1을 그대로 유지한다
      // (일자별 재압축은 하지 않음).
      expect(layout.laneGrid[4][0], isNull);
      expect(layout.laneGrid[4][1], isNotNull);
      expect(layout.overflowCounts, everyElement(0));
    });

    test('maxLanes를 넘는 대회는 줄로 못 그리고 overflow로 집계된다', () {
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final sameDay = DateTime(2026, 7, 15);
      final layout = laneLayoutForWeek(
        week,
        [for (var i = 0; i < 6; i++) _t(start: sameDay)],
        maxLanes: 4,
      );
      final placedLanes =
          layout.laneGrid[2].where((slot) => slot != null).length;
      expect(placedLanes, 4);
      expect(layout.overflowCounts[2], 2); // 6개 중 4개만 줄로 그림
      expect(layout.overflowCounts[1], 0); // 대회 없는 날은 overflow도 0
    });
  });
}
