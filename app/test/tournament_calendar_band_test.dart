import 'package:allround/models/tournament.dart';
import 'package:allround/screens/tournaments/tournaments_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 최소 필드만 채운 대회. 밴드 판정은 startDate/endDate만 사용한다.
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
  group('multiDayBandOnDate', () {
    final multiDay = [
      _t(start: DateTime(2026, 7, 15), end: DateTime(2026, 7, 19))
    ];

    test('멀티데이 대회 기간 안/밖 판정', () {
      expect(multiDayBandOnDate(DateTime(2026, 7, 14), multiDay), isFalse);
      expect(multiDayBandOnDate(DateTime(2026, 7, 15), multiDay), isTrue);
      expect(multiDayBandOnDate(DateTime(2026, 7, 17), multiDay), isTrue);
      expect(multiDayBandOnDate(DateTime(2026, 7, 19), multiDay), isTrue);
      expect(multiDayBandOnDate(DateTime(2026, 7, 20), multiDay), isFalse);
    });

    test('하루짜리(endDate null / start==end)는 밴드 없음', () {
      final oneDayNull = [_t(start: DateTime(2026, 7, 16))];
      final oneDaySame = [
        _t(start: DateTime(2026, 7, 16), end: DateTime(2026, 7, 16))
      ];
      expect(multiDayBandOnDate(DateTime(2026, 7, 16), oneDayNull), isFalse);
      expect(multiDayBandOnDate(DateTime(2026, 7, 16), oneDaySame), isFalse);
    });

    test('null 날짜는 false', () {
      expect(multiDayBandOnDate(null, multiDay), isFalse);
    });
  });

  group('bandFlagsForWeek', () {
    test('주 중간에 걸친 구간: 시작/중간/끝 모서리', () {
      final week = [
        for (var d = 13; d <= 19; d++) DateTime(2026, 7, d),
      ];
      final flags = bandFlagsForWeek(
        week,
        [_t(start: DateTime(2026, 7, 15), end: DateTime(2026, 7, 19))],
      );
      // 13, 14: 밴드 없음
      expect(flags[0].hasBand, isFalse);
      expect(flags[1].hasBand, isFalse);
      // 15: 구간 시작
      expect(flags[2].hasBand, isTrue);
      expect(flags[2].isBandStart, isTrue);
      expect(flags[2].isBandEnd, isFalse);
      // 16~18: 중간 (양쪽 각짐)
      for (final i in [3, 4, 5]) {
        expect(flags[i].hasBand, isTrue);
        expect(flags[i].isBandStart, isFalse);
        expect(flags[i].isBandEnd, isFalse);
      }
      // 19: Row 마지막 → 끝
      expect(flags[6].isBandStart, isFalse);
      expect(flags[6].isBandEnd, isTrue);
    });

    test('주간 경계: 토요일 셀은 시작이자 끝(Row 마지막 + 왼쪽 없음)', () {
      // 대회 7/18(토)~7/20(월). 첫 주 마지막 칸이 7/18.
      final tour = [
        _t(start: DateTime(2026, 7, 18), end: DateTime(2026, 7, 20))
      ];
      final firstWeek = [
        for (var d = 12; d <= 18; d++) DateTime(2026, 7, d),
      ];
      final firstFlags = bandFlagsForWeek(firstWeek, tour);
      expect(firstFlags[6].hasBand, isTrue); // 7/18
      expect(firstFlags[6].isBandStart, isTrue); // 왼쪽(7/17) 밴드 없음
      expect(firstFlags[6].isBandEnd, isTrue); // Row 마지막

      final nextWeek = [
        for (var d = 19; d <= 25; d++) DateTime(2026, 7, d),
      ];
      final nextFlags = bandFlagsForWeek(nextWeek, tour);
      expect(nextFlags[0].isBandStart, isTrue); // 7/19 Row 처음
      expect(nextFlags[0].isBandEnd, isFalse);
      expect(nextFlags[1].isBandStart, isFalse); // 7/20 끝
      expect(nextFlags[1].isBandEnd, isTrue);
      expect(nextFlags[2].hasBand, isFalse); // 7/21
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
      final flags = bandFlagsForWeek(week, tour);
      expect(flags[2].hasBand, isTrue); // 7/1
      expect(flags[2].isBandStart, isTrue); // 왼쪽 null
      expect(flags[3].isBandEnd, isTrue); // 7/2 끝
      expect(flags[4].hasBand, isFalse); // 7/3
    });
  });
}
