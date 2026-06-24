import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/utils/active_filters.dart';
import 'package:matchup/utils/tournament_filters.dart';

void main() {
  final now = DateTime(2026, 6, 15);

  List<ActiveFilterChipData> chipsFor({
    String? sport = 'tennis',
    String query = '',
    String? regionCode,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? hostOrg,
    Set<String> divisionCodes = const {},
    RecruitingStatus recruiting = RecruitingStatus.all,
    bool onlyMyGrade = false,
  }) =>
      activeFilterChips(
        sport: sport,
        query: query,
        regionCode: regionCode,
        dateFrom: dateFrom,
        dateTo: dateTo,
        hostOrg: hostOrg,
        divisionCodes: divisionCodes,
        recruiting: recruiting,
        onlyMyGrade: onlyMyGrade,
        now: now,
      );

  group('activeFilterChips — 산출', () {
    test('필터 없음 → 빈 리스트', () {
      expect(chipsFor(), isEmpty);
    });

    test('검색어는 따옴표로 감싼다', () {
      final chips = chipsFor(query: '  빛고을  ');
      expect(chips.single.kind, ActiveFilterKind.query);
      expect(chips.single.label, '"빛고을"');
    });

    test('공백만 있는 검색어는 칩 없음', () {
      expect(chipsFor(query: '   '), isEmpty);
    });

    test('지역 → 한글 라벨', () {
      final chips = chipsFor(regionCode: 'jeonnam');
      expect(chips.single.kind, ActiveFilterKind.region);
      expect(chips.single.label, '전남');
    });

    test('협회 → short label', () {
      final chips = chipsFor(hostOrg: 'gj');
      expect(chips.single.kind, ActiveFilterKind.hostOrg);
      expect(chips.single.label, '광주협회');
    });

    test('모집상태/내 등급만', () {
      final chips = chipsFor(
        recruiting: RecruitingStatus.recruiting,
        onlyMyGrade: true,
      );
      expect(chips.map((c) => c.label), containsAll(['모집중', '내 등급만']));
    });

    test('칩 순서: 검색어 → 지역 → 기간 → 협회 → 부서 → 모집 → 내등급', () {
      final chips = chipsFor(
        query: 'a',
        regionCode: 'gwangju',
        dateFrom: DateTime(2026, 6, 1),
        dateTo: DateTime(2026, 6, 30),
        hostOrg: 'gj',
        divisionCodes: {'gj_m_gold'},
        recruiting: RecruitingStatus.closed,
        onlyMyGrade: true,
      );
      expect(
        chips.map((c) => c.kind).toList(),
        [
          ActiveFilterKind.query,
          ActiveFilterKind.region,
          ActiveFilterKind.dateRange,
          ActiveFilterKind.hostOrg,
          ActiveFilterKind.division,
          ActiveFilterKind.recruiting,
          ActiveFilterKind.onlyMyGrade,
        ],
      );
    });
  });

  group('기간 칩 라벨', () {
    test('당월 범위 → "당월"', () {
      expect(
        dateRangeChipLabel(DateTime(2026, 6, 1), DateTime(2026, 6, 30), now),
        '당월',
      );
    });

    test('임의 범위 → "MM.DD~MM.DD"', () {
      expect(
        dateRangeChipLabel(DateTime(2026, 6, 10), DateTime(2026, 6, 20), now),
        '06.10~06.20',
      );
    });

    test('null/null → "기간" (fallback)', () {
      expect(dateRangeChipLabel(null, null, now), '기간');
    });
  });

  group('부서 칩 (테니스: 라벨 단위)', () {
    test('같은 라벨 여러 협회 코드 → 라벨 1개 칩', () {
      final chips = chipsFor(divisionCodes: {'gj_m_gold', 'jn_m_gold'});
      final division =
          chips.where((c) => c.kind == ActiveFilterKind.division).toList();
      expect(division.length, 1);
      expect(division.single.label, '골드부');
      expect(division.single.value, '골드부');
    });

    test('서로 다른 라벨 → 각각 칩', () {
      final chips = chipsFor(divisionCodes: {'gj_m_gold', 'gj_m_general'});
      final labels = chips
          .where((c) => c.kind == ActiveFilterKind.division)
          .map((c) => c.label)
          .toSet();
      expect(labels, {'골드부', '일반부'});
    });
  });

  group('등급 칩 (풋살: 코드 단위)', () {
    test('풋살 등급 → 한글 라벨, value=코드', () {
      final chips = chipsFor(
        sport: 'futsal',
        divisionCodes: {'intro', 'advanced'},
      );
      final division =
          chips.where((c) => c.kind == ActiveFilterKind.division).toList();
      expect(division.map((c) => c.label).toSet(), {'입문', '고급'});
      expect(division.map((c) => c.value).toSet(), {'intro', 'advanced'});
    });
  });

  group('removeTennisDivisionLabel', () {
    test('해당 라벨 코드만 제거 (다른 협회 같은 라벨 포함)', () {
      final result = removeTennisDivisionLabel(
        {'gj_m_gold', 'jn_m_gold', 'gj_m_general'},
        '골드부',
      );
      expect(result, {'gj_m_general'});
    });

    test('없는 라벨 → 변화 없음', () {
      final input = {'gj_m_gold'};
      expect(removeTennisDivisionLabel(input, '일반부'), input);
    });
  });
}
