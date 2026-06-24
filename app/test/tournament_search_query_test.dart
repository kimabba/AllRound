import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/services/api.dart';

void main() {
  group('buildTournamentSearchQuery', () {
    test('빈 필터는 항상 보내는 키만 포함', () {
      final q = buildTournamentSearchQuery();
      expect(q.keys.toSet(), {'only_my_grade', 'limit', 'offset'});
      expect(q['only_my_grade'], 'true');
      expect(q['limit'], '50');
      expect(q['offset'], '0');
    });

    test('region_code / org / division_codes 키 매핑', () {
      final q = buildTournamentSearchQuery(
        sport: 'tennis',
        regionCode: 'gwangju',
        hostOrg: 'kta',
        divisionCodes: const ['gj_m_gold', 'jn_m_gold'],
        onlyMyGrade: false,
        query: '오픈',
        limit: 100,
      );
      expect(q['sport'], 'tennis');
      expect(q['region_code'], 'gwangju');
      expect(q['org'], 'kta');
      // division_codes 는 쉼표 join
      expect(q['division_codes'], 'gj_m_gold,jn_m_gold');
      expect(q['only_my_grade'], 'false');
      expect(q['q'], '오픈');
      expect(q['limit'], '100');
    });

    test('date_from / date_to 는 YYYY-MM-DD (zero-padded)', () {
      final q = buildTournamentSearchQuery(
        dateFrom: DateTime(2026, 6, 1),
        dateTo: DateTime(2026, 12, 31),
      );
      expect(q['date_from'], '2026-06-01');
      expect(q['date_to'], '2026-12-31');
    });

    test('빈 문자열/빈 리스트는 키 생략', () {
      final q = buildTournamentSearchQuery(
        sport: '',
        regionCode: '',
        hostOrg: '',
        divisionCodes: const [],
        query: '',
      );
      expect(q.containsKey('sport'), isFalse);
      expect(q.containsKey('region_code'), isFalse);
      expect(q.containsKey('org'), isFalse);
      expect(q.containsKey('division_codes'), isFalse);
      expect(q.containsKey('q'), isFalse);
      expect(q.containsKey('date_from'), isFalse);
      expect(q.containsKey('date_to'), isFalse);
    });

    test('단일 division_code 도 그대로 전달', () {
      final q = buildTournamentSearchQuery(divisionCodes: const ['intro']);
      expect(q['division_codes'], 'intro');
    });

    test('recruiting → recruiting 키 (open/closed)', () {
      expect(buildTournamentSearchQuery(recruiting: 'open')['recruiting'],
          'open');
      expect(buildTournamentSearchQuery(recruiting: 'closed')['recruiting'],
          'closed');
    });

    test('recruiting null/빈문자열 → 키 생략', () {
      expect(buildTournamentSearchQuery().containsKey('recruiting'), isFalse);
      expect(
          buildTournamentSearchQuery(recruiting: '').containsKey('recruiting'),
          isFalse);
    });
  });
}
