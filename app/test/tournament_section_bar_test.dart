import 'package:allround/widgets/tournament_section_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('대회 하위 띠에 대회·랭킹·룰북을 표시한다', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: TournamentSectionBar(
              selected: TournamentSection.overview,
            ),
          ),
        ),
        GoRoute(
          path: '/rankings',
          builder: (_, __) => const Scaffold(body: Text('랭킹 화면')),
        ),
        GoRoute(
          path: '/rules',
          builder: (_, __) => const Scaffold(body: Text('룰북 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final tournamentX = tester.getCenter(find.text('대회')).dx;
    final rankingsX = tester.getCenter(find.text('랭킹')).dx;
    final rulesX = tester.getCenter(find.text('룰북')).dx;
    expect(tournamentX, lessThan(rankingsX));
    expect(rankingsX, lessThan(rulesX));

    await tester.tap(find.text('랭킹'));
    await tester.pumpAndSettle();
    expect(find.text('랭킹 화면'), findsOneWidget);
  });

  testWidgets('대회 하위 띠는 320px에서 48px 터치 높이를 지킨다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: TournamentSectionBar(
              selected: TournamentSection.overview,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(
      tester.getSize(find.byType(TournamentSectionBar)).height,
      48,
    );
    expect(tester.takeException(), isNull);
  });
}
