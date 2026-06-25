import 'package:flutter_test/flutter_test.dart';
import 'package:allround/utils/tournament_filters.dart';

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

  group('recruitingStatusToParam (서버 쿼리 매핑)', () {
    test('all → null (미전송)', () {
      expect(recruitingStatusToParam(RecruitingStatus.all), isNull);
    });

    test('recruiting → "open"', () {
      expect(recruitingStatusToParam(RecruitingStatus.recruiting), 'open');
    });

    test('closed → "closed"', () {
      expect(recruitingStatusToParam(RecruitingStatus.closed), 'closed');
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
