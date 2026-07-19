import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:allround/widgets/global_chat_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pureform fixed component sizes stay on the documented contract', () {
    expect(AppSizes.touchTarget, 48);
    expect(AppSizes.control, 48);
    expect(AppSizes.appBar, 56);
    expect(AppSizes.listRow, 56);
    expect(AppSizes.globalChatDock, 60);
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
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GlobalChatDock(location: '/'),
                  AppBottomNav(currentIndex: 0, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('AI에게 물어보기'), findsOneWidget);
    expect(find.text('오늘에서 바로 질문'), findsOneWidget);
    expect(find.text('오늘'), findsOneWidget);
    expect(find.text('MY'), findsOneWidget);
  });

  testWidgets('200% text keeps the global AI dock within its fixed region',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox.expand(),
            bottomNavigationBar: GlobalChatDock(location: '/'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('AI에게 물어보기'), findsOneWidget);
    expect(find.text('오늘에서 바로 질문'), findsNothing);
    expect(
      tester.getSize(find.byType(GlobalChatDock)),
      const Size(320, AppSizes.globalChatDock),
    );
  });
}
