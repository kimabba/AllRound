import 'package:allround/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('이전 기록이 없으면 지정한 기본 화면으로 돌아간다', (tester) async {
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/clubs',
          builder: (_, __) => const Scaffold(body: Text('모임 목록')),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, __) => Scaffold(
            appBar: AppBar(
              leading: const AppBackButton(fallbackLocation: '/clubs'),
            ),
            body: const Text('모임 상세'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('모임 목록'), findsOneWidget);
  });
}
