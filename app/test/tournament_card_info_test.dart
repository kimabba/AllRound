import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/tournament_card_info.dart';

void main() {
  // 날짜만 비교하므로 테스트는 intl 로케일 초기화 없이 간단한 포매터를 주입한다.
  String fmt(DateTime d) => '${d.month}/${d.day}';

  group('DeadlineInfo.compute — 마감 상태', () {
    final today = DateTime(2026, 6, 24);

    test('마감일 미정 → none, daysLeft null, D-day 빈 문자열', () {
      final info = DeadlineInfo.compute(null, today);
      expect(info.status, DeadlineStatus.none);
      expect(info.daysLeft, isNull);
      expect(info.ddayBadge, '');
    });

    test('마감 지남 → passed, D-day 빈 문자열', () {
      final info = DeadlineInfo.compute(DateTime(2026, 6, 23), today);
      expect(info.status, DeadlineStatus.passed);
      expect(info.daysLeft, -1);
      expect(info.ddayBadge, '');
    });

    test('당일 → today, D-Day', () {
      final info = DeadlineInfo.compute(DateTime(2026, 6, 24, 23, 59), today);
      expect(info.status, DeadlineStatus.today);
      expect(info.daysLeft, 0);
      expect(info.ddayBadge, 'D-Day');
    });

    test('1~7일 남음 → soon, D-N', () {
      final info = DeadlineInfo.compute(DateTime(2026, 6, 27), today);
      expect(info.status, DeadlineStatus.soon);
      expect(info.daysLeft, 3);
      expect(info.ddayBadge, 'D-3');
    });

    test('8일 이상 남음 → open, D-day 빈 문자열', () {
      final info = DeadlineInfo.compute(DateTime(2026, 7, 10), today);
      expect(info.status, DeadlineStatus.open);
      expect(info.ddayBadge, '');
    });
  });

  group('tournamentDateText — 대회일/기간', () {
    test('endDate 없음 → 시작일만', () {
      expect(tournamentDateText(DateTime(2026, 6, 13), null, fmt), '6/13');
    });

    test('endDate가 시작과 같은 날 → 시작일만', () {
      expect(
        tournamentDateText(DateTime(2026, 6, 13), DateTime(2026, 6, 13), fmt),
        '6/13',
      );
    });

    test('다중일 → 시작~종료', () {
      expect(
        tournamentDateText(DateTime(2026, 6, 13), DateTime(2026, 6, 15), fmt),
        '6/13~6/15',
      );
    });
  });

  group('applicationDeadlineText — 신청 마감', () {
    test('마감일 있음 → ~M/D 마감', () {
      expect(applicationDeadlineText(DateTime(2026, 6, 20), fmt), '~6/20 마감');
    });

    test('마감일 미정 → 빈 문자열', () {
      expect(applicationDeadlineText(null, fmt), '');
    });
  });

  group('locationText — 위치(location 우선, region 폴백)', () {
    test('location + region → "location · region"', () {
      expect(locationText('영암종합스포츠타운', '전남'), '영암종합스포츠타운 · 전남');
    });

    test('location만 → location', () {
      expect(locationText('진월국제테니스장', null), '진월국제테니스장');
    });

    test('location null → region 폴백', () {
      expect(locationText(null, '광주'), '광주');
    });

    test('location == region → 중복 제거(하나만)', () {
      expect(locationText('광주', '광주'), '광주');
    });

    test('둘 다 없음 → 빈 문자열', () {
      expect(locationText(null, null), '');
      expect(locationText('  ', ''), '');
    });
  });
}
