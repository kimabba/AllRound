import 'dart:async';

import 'package:allround/models/tournament.dart';
import 'package:allround/screens/admin/no_access_screen.dart';
import 'package:allround/screens/home_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required Future<List<Tournament>> Function() load,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        // main.dart 와 동일하게 riverpod 3 자동 재시도를 끈다(에러 상태 정착 보장).
        retry: (_, __) => null,
        overrides: [
          homeTournamentsProvider.overrideWith((ref) => load()),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const HomeScreen(),
          ),
        ),
      ),
    );
  }

  void useSmallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> revealHomeContent(WidgetTester tester) async {
    final scrollView = find.byType(CustomScrollView);
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.drag(scrollView, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('home exposes a deterministic loading skeleton', (tester) async {
    final pending = Completer<List<Tournament>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const []);
    });

    await pumpHome(tester, load: () => pending.future);
    await tester.pump();

    expect(find.byKey(AllRoundE2EKeys.homeLoadingState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home empty state remains usable at 200% text in dark mode',
      (tester) async {
    useSmallPhone(tester);
    await pumpHome(
      tester,
      load: () async => const [],
      theme: AppTheme.dark(),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    await revealHomeContent(tester);

    expect(find.byKey(AllRoundE2EKeys.homeEmptyState), findsOneWidget);
    expect(find.text('전체 대회 보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home offline failure shows an actionable retry state',
      (tester) async {
    useSmallPhone(tester);
    await pumpHome(
      tester,
      load: () => Future<List<Tournament>>.error(
        TimeoutException('offline'),
      ),
      theme: AppTheme.dark(),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    await revealHomeContent(tester);

    expect(find.byKey(AllRoundE2EKeys.homeErrorState), findsOneWidget);
    expect(find.text('연결 상태를 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(find.text('다시 불러오기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long Korean tournament content stays bounded at 200% text',
      (tester) async {
    useSmallPhone(tester);
    final now = DateTime.now();
    await pumpHome(
      tester,
      load: () async => [
        Tournament(
          id: 'qa-long-korean',
          sport: 'tennis',
          title: '전국 생활체육 테니스 동호인을 위한 매우 긴 이름의 여름 야간 복식 챔피언십',
          organizer: 'QA',
          startDate: now.add(const Duration(days: 3)),
          applicationDeadline: now.add(const Duration(days: 1)),
          region: '서울특별시',
          location: '서울특별시의 매우 긴 이름을 가진 국제 규격 실내외 복합 테니스 경기장',
          eligibleGrades: const ['open'],
          status: 'published',
        ),
      ],
      theme: AppTheme.dark(),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    await revealHomeContent(tester);

    expect(find.byKey(AllRoundE2EKeys.homeTournamentList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission-denied screen remains readable at 200% text',
      (tester) async {
    useSmallPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: NoAccessScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('관리자 권한이 필요합니다'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
