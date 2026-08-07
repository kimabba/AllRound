import 'package:allround/models/tournament.dart';
import 'package:allround/screens/clubs/club_detail_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('모임 생성 시트는 작은 화면의 키보드 위에서 스크롤된다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final club = Club(
      id: 'keyboard-test-club',
      sport: 'tennis',
      name: '키보드 테스트 클럽',
      region: '서울',
      memberCount: 8,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Material(child: ClubEventCreateSheet(club: club)),
        ),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scrollView.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
    expect(find.text('만들기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -240));
    await tester.pump();
    expect(find.text('만들기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
