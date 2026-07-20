import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pureform fixed component sizes stay on the documented contract', () {
    expect(AppSizes.touchTarget, 48);
    expect(AppSizes.control, 48);
    expect(AppSizes.appBar, 56);
    expect(AppSizes.listRow, 56);
    expect(AppSizes.bottomNavigation, 64);
  });

  testWidgets('small screen and 130% text keep the bottom action region usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(
                currentIndex: 0,
                onChanged: (_) {},
                onChatTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('MY'), findsOneWidget);
  });

  testWidgets('200% text keeps the bottom nav within its fixed region',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onChanged: (_) {},
              onChatTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppBottomNav)),
      const Size(320, AppSizes.bottomNavigation + bottomNavDialProtrusion),
    );
  });
}
