import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/profile/my_record_widgets.dart';

// AppTheme.light 는 게터가 아니라 메서드다(app/lib/theme/app_theme.dart:9).
// 테마를 빼면 안 된다 — 이 프로젝트 테마가 버튼 폭을 무한으로 강제해서,
// 테마 없이 통과한 위젯이 실기기에서 크래시한 전례가 있다.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

PlayerResult _r({
  required String name,
  required String raw,
  int? round,
  required int points,
  required String on,
}) =>
    PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': name,
      'played_on': on,
      'result_raw': raw,
      'result_round': round,
      'points': points,
    });

OrgRankingRow _rank({required String div, required int rank, required int pts}) =>
    OrgRankingRow.fromJson({
      'org_code': 'gj',
      'division_code': div,
      'rank': rank,
      'player_name': 'zz선수',
      'rank_points': pts,
      'total_points': pts,
    });

void main() {
  testWidgets('현재 순위 블록을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(
      results: const [],
      rankings: [_rank(div: 'gj_m_gold', rank: 12, pts: 1500)],
    )));
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('1500'), findsWidgets);
  });

  testWidgets('전적이 있으면 최고의 순간과 타임라인을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '광주시장배', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
      _r(name: '봄철대회', raw: '16강', round: 16, points: 60, on: '2026-03-01'),
    ])));
    expect(find.text('광주시장배'), findsWidgets);
    expect(find.text('우승'), findsWidgets);
    expect(find.text('16강'), findsWidgets);
  });

  testWidgets('최고의 순간은 포인트가 가장 높은 대회다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '작은대회', raw: '4강', round: 4, points: 100, on: '2026-06-01'),
      _r(name: '큰대회', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
    ])));
    // 두 대회 모두 전적 타임라인에는 나열되므로, textContaining 만으로는
    // best 선택 로직을 검증하지 못한다 — "최고의 순간" 카드 안으로 좁힌다.
    final bestCard = find.byKey(const Key('best-moment-card'));
    expect(
      find.descendant(of: bestCard, matching: find.textContaining('큰대회')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bestCard, matching: find.textContaining('작은대회')),
      findsNothing,
    );
  });

  testWidgets('정규화 실패 행은 협회 원문을 그대로 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: 'zz대회', raw: '예선탈락', round: null, points: 5, on: '2026-05-01'),
    ])));
    expect(find.text('예선탈락'), findsWidgets);
  });

  testWidgets('전적이 없으면 안내를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(const RecordContent(results: [])));
    expect(find.textContaining('전적'), findsWidgets);
  });

  testWidgets('긴 협회 원문 결과 라벨이 있어도 좁은 화면에서 오버플로우가 나지 않는다',
      (tester) async {
    // 넓은 기본 테스트 캔버스(800x600)에서는 이 정도 길이로도 넘치지 않는다 —
    // 실제로 문제가 재현되는 작은 화면 폭으로 좁혀야 회귀를 잡는 테스트가 된다.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(
        name: '전남지사배 전국테니스대회',
        raw: '예선탈락(1회전 세트스코어 0:2 패배로 조기 탈락, 재경기 없음)',
        round: null,
        points: 5,
        on: '2026-05-01',
      ),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 원문은 자르지 않고 그대로 보여준다 — 레이아웃만 안전해야 한다.
    expect(find.text('예선탈락(1회전 세트스코어 0:2 패배로 조기 탈락, 재경기 없음)'), findsOneWidget);
  });
}
