import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament_card_info.dart';

void main() {
  String fmt(DateTime d) => '${d.month}/${d.day}';

  group('DeadlineInfo.compute -- edge cases', () {
    test('마감이 오래 전(30일 전) -> passed, daysLeft -30', () {
      final today = DateTime(2026, 7, 30);
      final info = DeadlineInfo.compute(DateTime(2026, 6, 30), today);
      expect(info.status, DeadlineStatus.passed);
      expect(info.daysLeft, -30);
      expect(info.ddayBadge, '');
    });

    test('마감 정확히 7일 남음 -> soon, D-7', () {
      final today = DateTime(2026, 6, 24);
      final info = DeadlineInfo.compute(DateTime(2026, 7, 1), today);
      expect(info.status, DeadlineStatus.soon);
      expect(info.daysLeft, 7);
      expect(info.ddayBadge, 'D-7');
    });

    test('마감 정확히 8일 남음 -> open, 빈 badge', () {
      final today = DateTime(2026, 6, 24);
      final info = DeadlineInfo.compute(DateTime(2026, 7, 2), today);
      expect(info.status, DeadlineStatus.open);
      expect(info.daysLeft, 8);
      expect(info.ddayBadge, '');
    });

    test('마감 정확히 1일 남음 -> soon, D-1', () {
      final today = DateTime(2026, 6, 24);
      final info = DeadlineInfo.compute(DateTime(2026, 6, 25), today);
      expect(info.status, DeadlineStatus.soon);
      expect(info.daysLeft, 1);
      expect(info.ddayBadge, 'D-1');
    });

    test('마감일에 시각 성분이 있어도 날짜만 비교 (23:59:59)', () {
      final today = DateTime(2026, 6, 24, 8, 0);
      final deadline = DateTime(2026, 6, 24, 23, 59, 59);
      final info = DeadlineInfo.compute(deadline, today);
      expect(info.status, DeadlineStatus.today);
      expect(info.daysLeft, 0);
    });

    test('today에 시각 성분이 있어도 날짜만 비교', () {
      final today = DateTime(2026, 6, 24, 23, 59, 59);
      final deadline = DateTime(2026, 6, 25);
      final info = DeadlineInfo.compute(deadline, today);
      expect(info.status, DeadlineStatus.soon);
      expect(info.daysLeft, 1);
    });

    test('연도가 다른 경우 (올해 마감, 작년 today)', () {
      final today = DateTime(2025, 12, 31);
      final deadline = DateTime(2026, 1, 1);
      final info = DeadlineInfo.compute(deadline, today);
      expect(info.status, DeadlineStatus.soon);
      expect(info.daysLeft, 1);
    });
  });

  group('tournamentDateText -- edge cases', () {
    test('endDate가 시작보다 이전이면 범위로 표시', () {
      // 비정상 데이터: endDate < startDate. 함수는 isSameCalendarDay 만 확인.
      expect(
        tournamentDateText(DateTime(2026, 6, 15), DateTime(2026, 6, 10), fmt),
        '6/15~6/10',
      );
    });

    test('같은 날의 다른 시각 -> 단일일로 표시', () {
      expect(
        tournamentDateText(
          DateTime(2026, 6, 13, 9, 0),
          DateTime(2026, 6, 13, 18, 0),
          fmt,
        ),
        '6/13',
      );
    });
  });

  group('applicationDeadlineText -- edge cases', () {
    test('마감일 1월 1일 -> ~1/1 마감', () {
      expect(applicationDeadlineText(DateTime(2026, 1, 1), fmt), '~1/1 마감');
    });
  });

  group('locationText -- edge cases', () {
    test('location이 빈 문자열, region null -> 빈 문자열', () {
      expect(locationText('', null), '');
    });

    test('location null, region 빈 문자열 -> 빈 문자열', () {
      expect(locationText(null, ''), '');
    });

    test('location과 region 모두 공백만 -> 빈 문자열', () {
      expect(locationText('  ', '  '), '');
    });

    test('location이 region과 동일한 앞뒤공백 포함 -> 중복 제거', () {
      expect(locationText(' 광주 ', ' 광주 '), '광주');
    });
  });

  group('isSameCalendarDay', () {
    test('동일 날짜 다른 시각 -> true', () {
      expect(
        isSameCalendarDay(DateTime(2026, 6, 15, 0), DateTime(2026, 6, 15, 23)),
        isTrue,
      );
    });

    test('하루 차이 -> false', () {
      expect(
        isSameCalendarDay(DateTime(2026, 6, 15), DateTime(2026, 6, 16)),
        isFalse,
      );
    });
  });
}
