import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';

void main() {
  test('fromJson이 스냅샷 한 행을 그대로 옮긴다', () {
    final s = OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'vudghk2116',
      'captured_on': '2026-08-04',
      'rank': 1,
      'total_points': 2649,
    });

    expect(s.orgCode, 'gj');
    expect(s.divisionCode, 'gj_m_gold');
    expect(s.orgPlayerId, 'vudghk2116');
    expect(s.capturedOn, DateTime.parse('2026-08-04'));
    expect(s.rank, 1);
    expect(s.totalPoints, 2649);
  });
}
