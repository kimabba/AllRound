import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/utils/tournament_filters.dart';

void main() {
  group('dateRangeForPreset', () {
    test('전체/직접선택 → (null, null)', () {
      final now = DateTime(2026, 6, 15);
      expect(dateRangeForPreset(DatePreset.all, now), (null, null));
      expect(dateRangeForPreset(DatePreset.custom, now), (null, null));
    });

    test('당월: 1일 ~ 말일 (6월 = 30일)', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.thisMonth, DateTime(2026, 6, 15));
      expect(from, DateTime(2026, 6, 1));
      expect(to, DateTime(2026, 6, 30));
    });

    test('당월 말일: 2월 윤년 경계 (2024-02 = 29일)', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.thisMonth, DateTime(2024, 2, 10));
      expect(from, DateTime(2024, 2, 1));
      expect(to, DateTime(2024, 2, 29));
    });

    test('익월: 다음 달 1일 ~ 말일', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.nextMonth, DateTime(2026, 6, 15));
      expect(from, DateTime(2026, 7, 1));
      expect(to, DateTime(2026, 7, 31));
    });

    test('익월 연말 경계: 12월 → 다음 해 1월', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.nextMonth, DateTime(2026, 12, 20));
      expect(from, DateTime(2027, 1, 1));
      expect(to, DateTime(2027, 1, 31));
    });

    test('당월 연말 경계: 12월 = 31일', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.thisMonth, DateTime(2026, 12, 1));
      expect(from, DateTime(2026, 12, 1));
      expect(to, DateTime(2026, 12, 31));
    });

    test('올해: 1/1 ~ 12/31', () {
      final (from, to) =
          dateRangeForPreset(DatePreset.thisYear, DateTime(2026, 6, 15));
      expect(from, DateTime(2026, 1, 1));
      expect(to, DateTime(2026, 12, 31));
    });
  });

  group('presetForRange (역추론)', () {
    final now = DateTime(2026, 6, 15);

    test('null/null → all', () {
      expect(presetForRange(null, null, now), DatePreset.all);
    });

    test('당월 범위 → thisMonth', () {
      expect(
        presetForRange(DateTime(2026, 6, 1), DateTime(2026, 6, 30), now),
        DatePreset.thisMonth,
      );
    });

    test('익월 범위 → nextMonth', () {
      expect(
        presetForRange(DateTime(2026, 7, 1), DateTime(2026, 7, 31), now),
        DatePreset.nextMonth,
      );
    });

    test('올해 범위 → thisYear', () {
      expect(
        presetForRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31), now),
        DatePreset.thisYear,
      );
    });

    test('임의 범위 → custom', () {
      expect(
        presetForRange(DateTime(2026, 6, 10), DateTime(2026, 6, 20), now),
        DatePreset.custom,
      );
    });

    test('한쪽만 있는 범위 → custom', () {
      expect(presetForRange(DateTime(2026, 6, 1), null, now), DatePreset.custom);
    });
  });

  group('isClosed', () {
    final today = DateTime(2026, 6, 24);

    test('deadline == null → 마감 아님', () {
      expect(isClosed(null, today), isFalse);
    });

    test('deadline 과거 → 마감', () {
      expect(isClosed(DateTime(2026, 6, 23), today), isTrue);
    });

    test('deadline 오늘 → 마감 아님 (>= today)', () {
      expect(isClosed(DateTime(2026, 6, 24), today), isFalse);
    });

    test('deadline 미래 → 마감 아님', () {
      expect(isClosed(DateTime(2026, 6, 25), today), isFalse);
    });

    test('시각이 달라도 날짜만 비교 (오늘 늦은 시각 deadline → 마감 아님)', () {
      expect(isClosed(DateTime(2026, 6, 24, 1, 0), DateTime(2026, 6, 24, 23, 59)),
          isFalse);
    });
  });

  group('matchesRecruiting', () {
    final today = DateTime(2026, 6, 24);

    test('all → 항상 통과', () {
      expect(matchesRecruiting(RecruitingStatus.all, null, today), isTrue);
      expect(
          matchesRecruiting(
              RecruitingStatus.all, DateTime(2020, 1, 1), today),
          isTrue);
    });

    test('recruiting: null/오늘/미래 통과, 과거 탈락', () {
      expect(matchesRecruiting(RecruitingStatus.recruiting, null, today),
          isTrue);
      expect(
          matchesRecruiting(
              RecruitingStatus.recruiting, DateTime(2026, 6, 24), today),
          isTrue);
      expect(
          matchesRecruiting(
              RecruitingStatus.recruiting, DateTime(2026, 7, 1), today),
          isTrue);
      expect(
          matchesRecruiting(
              RecruitingStatus.recruiting, DateTime(2026, 6, 23), today),
          isFalse);
    });

    test('closed: 과거만 통과, null/오늘/미래 탈락', () {
      expect(matchesRecruiting(RecruitingStatus.closed, null, today), isFalse);
      expect(
          matchesRecruiting(
              RecruitingStatus.closed, DateTime(2026, 6, 24), today),
          isFalse);
      expect(
          matchesRecruiting(
              RecruitingStatus.closed, DateTime(2026, 6, 25), today),
          isFalse);
      expect(
          matchesRecruiting(
              RecruitingStatus.closed, DateTime(2026, 6, 23), today),
          isTrue);
    });

    test('recruiting/closed 는 상호 배타 (deadline 별로 정확히 한쪽)', () {
      final deadlines = [
        null,
        DateTime(2026, 6, 23),
        DateTime(2026, 6, 24),
        DateTime(2026, 6, 25),
      ];
      for (final d in deadlines) {
        final r = matchesRecruiting(RecruitingStatus.recruiting, d, today);
        final c = matchesRecruiting(RecruitingStatus.closed, d, today);
        expect(r, isNot(c), reason: 'deadline=$d 는 정확히 한 상태여야 함');
      }
    });
  });

  group('labels', () {
    test('datePresetLabel', () {
      expect(datePresetLabel(DatePreset.all), '전체');
      expect(datePresetLabel(DatePreset.thisMonth), '당월');
      expect(datePresetLabel(DatePreset.nextMonth), '익월');
      expect(datePresetLabel(DatePreset.thisYear), '올해');
      expect(datePresetLabel(DatePreset.custom), '직접선택');
    });

    test('recruitingStatusLabel', () {
      expect(recruitingStatusLabel(RecruitingStatus.all), '전체');
      expect(recruitingStatusLabel(RecruitingStatus.recruiting), '모집중');
      expect(recruitingStatusLabel(RecruitingStatus.closed), '마감');
    });
  });
}
