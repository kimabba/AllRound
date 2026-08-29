import 'package:allround/screens/admin/admin_operations_home_screen.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('운영 홈은 대회 처리 흐름과 세 운영 영역을 한곳에 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('운영 작업의 시작점'), findsOneWidget);
    expect(find.text('제보 · Draft 검수'), findsOneWidget);
    expect(find.text('요강 정형화 검수'), findsOneWidget);
    expect(find.text('공개 대회 관리'), findsOneWidget);
    expect(find.text('수집 상태'), findsOneWidget);
    expect(find.text('지식베이스'), findsOneWidget);
    expect(find.text('협회 · 랭킹'), findsOneWidget);
    expect(find.text('클럽 · 커뮤니티'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('대회 운영 단계는 기존 관리자 경로로 이동한다', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    for (final route in const [
      (keyName: 'admin-home-drafts', path: '/admin/drafts'),
      (keyName: 'admin-home-format-review', path: '/admin/format-review'),
      (keyName: 'admin-home-tournaments', path: '/admin/tournaments'),
      (keyName: 'admin-home-crawl-status', path: '/admin/crawl-status'),
    ]) {
      router.go('/admin');
      await tester.pumpAndSettle();
      final action = find.byKey(ValueKey(route.keyName));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('destination-${route.path}')), findsOneWidget);
    }
  });

  testWidgets('운영 홈은 320px와 130% 글자에서 가로로 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('운영 작업의 시작점'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

GoRouter _router() {
  const paths = [
    '/admin/drafts',
    '/admin/format-review',
    '/admin/tournaments',
    '/admin/crawl-status',
    '/admin/sources',
    '/admin/kb',
    '/admin/ranking-claims',
    '/admin/clubs',
    '/admin/reports',
  ];

  return GoRouter(
    initialLocation: '/admin',
    routes: [
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminOperationsHomeScreen(),
      ),
      for (final path in paths)
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(
            body: SizedBox(
              key: ValueKey('destination-$path'),
              child: Text(path),
            ),
          ),
        ),
    ],
  );
}
