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

    test('시작 시점엔 레인이 다 찼어도 나중에 비면 그때부터 이어서 그려진다', () {
      // 13~15(월~수) 4개가 레인을 다 채우고, 14~18(화~토)짜리가 하나 더 있다.
      // 화/수는 5개가 겹쳐 1개가 진짜로 못 들어가지만, 목~토는 4개가 끝나서
      // 자리가 남는데도 전체를 overflow 처리하면 안 된다.
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final fullDays = [
        for (var i = 0; i < 4; i++)
          _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 15))
      ];
      final longRunning =
          _t(start: DateTime(2026, 7, 14), end: DateTime(2026, 7, 18));
      final layout = laneLayoutForWeek(week, [...fullDays, longRunning]);

      // 화(14)/수(15): 5개 겹침 → 1개는 이번 칸엔 자리가 없다.
      expect(layout.overflowCounts[1], 1); // 14
      expect(layout.overflowCounts[2], 1); // 15
      // 목~토(16~18): fullDays는 끝났고 longRunning만 남았으니 자리가 있어야 한다.
      for (final col in [3, 4, 5]) {
        expect(layout.overflowCounts[col], 0);
        expect(
          layout.laneGrid[col].where((slot) => slot != null).length,
          1,
        );
      }
      // 목(16)에서 새로 레인을 잡아 시작 모서리가 생기고, 토(18)에서 끝난다.
      final laneIndex =
          layout.laneGrid[3].indexWhere((slot) => slot != null);
      expect(layout.laneGrid[3][laneIndex]!.isBandStart, isTrue);
      expect(layout.laneGrid[5][laneIndex]!.isBandEnd, isTrue);
    });

    test('레인 한 개만 풀려도 나머지가 계속 점유 중인 채로 즉시 배정된다', () {
      // 4개가 서로 다른 날 끝나서(13/14/15/16) 레인이 한 번에 하나씩만 빈다.
      // "전부 다 풀려야 재배정" 하는 잘못된 구현이면 이 테스트가 실패해야 한다.
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final t1 = _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 13));
      final t2 = _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 14));
      final t3 = _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 15));
      final t4 = _t(start: DateTime(2026, 7, 13), end: DateTime(2026, 7, 16));
      final waiting =
          _t(start: DateTime(2026, 7, 14), end: DateTime(2026, 7, 19));
      final layout = laneLayoutForWeek(week, [t1, t2, t3, t4, waiting]);

      // 13(월): t1~t4가 4레인을 다 채운다. waiting은 아직 시작 전이라 없다.
      expect(layout.laneGrid[0].where((slot) => slot != null).length, 4);

      // 14(화): t1만 끝나 레인 하나만 빈다. t2/t3/t4는 그대로 자기 레인을
      // 이어서 쓰는 채(새로 시작한 게 아님)인데도, waiting이 그 하나 빈
      // 레인을 그 즉시 잡는다 — "전부 다 풀려야 재배정" 하는 구현이면
      // waiting 몫의 isBandStart가 하나도 안 잡혀야 한다.
      final startedAt14 =
          layout.laneGrid[1].where((slot) => slot?.isBandStart == true);
      expect(startedAt14.length, 1); // 새로 시작한 건 waiting 하나뿐
      expect(
        layout.laneGrid[1].where((slot) => slot != null).length,
        4, // t2,t3,t4 계속 + waiting 신규 = 4레인 다 참
      );
      final waitingLane = layout.laneGrid[1].indexWhere(
        (slot) => slot?.isBandStart == true,
      );
      // 19(일)에 waiting이 자연스럽게 끝난다(그 사이 같은 레인을 계속 쓴다).
      expect(layout.laneGrid[6][waitingLane]!.isBandEnd, isTrue);
      expect(layout.overflowCounts[1], 0); // 14: t1은 이미 끝나 4개만 겹치고, 4개 다 레인에 들어갔다
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
