import 'package:allround/screens/admin/admin_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('관리자 대회 검수 행동은 좁은 화면에서 줄바꿈되어 모두 보인다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(48),
            child: AdminTournamentReviewActions(
              onOpenDetails: () {},
              onOpenPreview: () {},
              onApprove: () {},
              onReject: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('등록 정보'), findsOneWidget);
    expect(find.text('사용자 미리보기'), findsOneWidget);
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('거절'), findsOneWidget);

    final detailsTop = tester.getTopLeft(find.text('등록 정보')).dy;
    final rejectTop = tester.getTopLeft(find.text('거절')).dy;
    expect(rejectTop, greaterThan(detailsTop));
  });
}
