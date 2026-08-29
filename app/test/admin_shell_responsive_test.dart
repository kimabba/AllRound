import 'package:allround/screens/admin/admin_operations_home_screen.dart';
import 'package:allround/screens/admin/admin_shell.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('실제 AdminShell은 320px에서 단일 AppBar와 닫히는 메뉴로 이동한다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        ShellRoute(
          builder: (_, __, child) => AdminShell(
            forceWebLayoutForTest: true,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/admin',
              builder: (_, __) => const AdminOperationsHomeScreen(),
            ),
            GoRoute(
              path: '/admin/drafts',
              builder: (_, __) => const _DraftDestinationScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('관리자 메뉴'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('관리자 메뉴'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-nav-/admin/drafts')));
    await tester.pumpAndSettle();

    expect(find.text('Draft 대상 화면'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('관리자 메뉴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DraftDestinationScreen extends StatelessWidget {
  const _DraftDestinationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: adminShellLeading(context),
        title: const Text('Draft 대상 화면'),
      ),
      body: const Center(child: Text('검수 화면이 표시되었습니다.')),
    );
  }
}
