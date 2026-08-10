import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/rankings/rank_trend_sparkline.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

OrgRankingSnapshot _s({required String on, required int rank}) =>
    OrgRankingSnapshot.fromJson({
      'org_code': 'gj',
      'division_code': 'gj_m_gold',
      'org_player_id': 'a',
      'captured_on': on,
      'rank': rank,
      'total_points': 1000,
    });

void main() {
  testWidgets('점이 0개면 안내 문구를 보여주고 그래프는 안 그린다', (tester) async {
    await tester.pumpWidget(_wrap(const RankTrendSparkline(snapshots: [])));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsOneWidget);
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('점이 1개여도 안내 문구를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [_s(on: '2026-08-04', rank: 5)],
    )));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsOneWidget);
  });

  testWidgets('점이 2개 이상이면 그래프를 그리고 안내 문구는 사라진다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [
        _s(on: '2026-08-04', rank: 5),
        _s(on: '2026-08-05', rank: 3),
      ],
    )));
    expect(find.text('추이를 보려면 며칠 더 필요해요'), findsNothing);
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('모든 순위가 같아도 0나눗셈 없이 그려진다', (tester) async {
    await tester.pumpWidget(_wrap(RankTrendSparkline(
      snapshots: [
        _s(on: '2026-08-04', rank: 5),
        _s(on: '2026-08-05', rank: 5),
        _s(on: '2026-08-06', rank: 5),
      ],
    )));
    expect(tester.takeException(), isNull);
  });
}
