import 'dart:async';

import 'package:allround/models/rule_quiz.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/admin/no_access_screen.dart';
import 'package:allround/screens/home_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  test('다가오는 대회는 풋살과 테니스 모두 3개만 표시한다', () {
    expect(homeTournamentDisplayLimit, 3);
  });

  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required Future<List<Tournament>> Function() load,
    ThemeData? theme,
    double textScale = 1,
    String? activeSport,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        // main.dart 와 동일하게 riverpod 3 자동 재시도를 끈다(에러 상태 정착 보장).
        retry: (_, __) => null,
        overrides: [
          homeTournamentsProvider.overrideWith((ref) => load()),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
          if (activeSport != null)
            activeSportProvider.overrideWith((ref) => activeSport),
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
    expect(find.text('대회'), findsOneWidget);
    expect(find.textContaining('올라운드 '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('관심 대회 빈 카드는 대회 목록으로 이동한다', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/tournaments',
          builder: (_, __) => const Scaffold(body: Text('대회 목록')),
        ),
        GoRoute(path: '/favorites', builder: (_, __) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, __) => null,
        overrides: [
          homeTournamentsProvider.overrideWith((ref) async => const []),
          myTournamentRecordsProvider.overrideWith((ref) async => const []),
          myClubsProvider.overrideWith((ref) async => const []),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('대회 둘러보기'));
    await tester.pumpAndSettle();
    expect(find.text('대회 목록'), findsOneWidget);
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

  // 목록 카드 배지가 지역 문자열의 첫 조각만 보면 선행 구분자('·서울')에서
  // "전국"으로 잘못 읽는다. 빈 조각을 건너뛰고 실제 지역을 보여줘야 한다.
  testWidgets('지역 배지는 선행 구분자를 건너뛰고 실제 지역을 보여준다', (tester) async {
    await pumpHome(
      tester,
      load: () async => [
        Tournament(
          id: 'seoul-1',
          sport: 'tennis',
          title: 'seoul-1 대회',
          organizer: 'QA',
          startDate: DateTime.now().add(const Duration(days: 3)),
          region: '·서울',
          eligibleGrades: const ['open'],
          status: 'published',
        ),
      ],
      activeSport: 'tennis',
    );
    await tester.pumpAndSettle();

    expect(find.text('서울'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 예전에는 종목 선택이 홈 화면 안에서만 살아 있어서, 홈에서 풋살로 바꿔도
  // 룰북 탭·전체 대회·클럽·챗봇은 프로필 주종목을 계속 봤다.
  testWidgets('타이틀에서 종목을 바꾸면 앱 전체 기준 종목이 바뀐다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        homeTournamentsProvider.overrideWith((ref) async => const []),
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('올라운드 '));
    await tester.pumpAndSettle();
    await tester.tap(find.text('테니스'));
    await tester.pumpAndSettle();

    expect(container.read(activeSportProvider), 'tennis');
    expect(find.textContaining('올라운드 테니스'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 예전에는 히어로·마감임박 가로줄·지역별 목록이 모두 같은 목록에서 뽑혀
  // 대회 하나가 한 화면에 세 번까지 나왔다.
  testWidgets('마감 임박 대회는 히어로와 목록에 한 번씩만 나온다', (tester) async {
    const title = '2026 마감임박 테스트 대회';
    await pumpHome(
      tester,
      load: () async => [
        Tournament(
          id: 'soon-1',
          sport: 'tennis',
          title: title,
          organizer: 'QA',
          startDate: DateTime.now().add(const Duration(days: 9)),
          applicationDeadline: DateTime.now().add(const Duration(days: 3)),
          region: '광주',
          eligibleGrades: const ['open'],
          status: 'published',
        ),
      ],
      activeSport: 'tennis',
    );
    await tester.pumpAndSettle();

    expect(find.text(title), findsNWidgets(2));
    expect(find.text('접수 마감 임박'), findsOneWidget);
    expect(find.text('다가오는 대회'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('퀴즈는 배너를 누른 뒤 보기 선택과 정답 확인으로 푼다', (tester) async {
    await pumpHome(
      tester,
      load: () async => const [],
      activeSport: 'tennis',
    );
    await tester.pumpAndSettle();

    final scrollView = find.byType(CustomScrollView);
    final quizLabel = find.text('오늘의 핵심 퀴즈');
    for (var attempt = 0;
        attempt < 8 && quizLabel.evaluate().isEmpty;
        attempt++) {
      await tester.drag(scrollView, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(quizLabel, findsOneWidget);
    await tester.ensureVisible(quizLabel);
    await tester.pumpAndSettle();

    expect(find.text('자세히 보기'), findsNothing);
    final quiz = dailyRuleQuiz('tennis');
    expect(find.text(quiz.explanation), findsNothing);

    await tester.tap(quizLabel);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('오늘의 룰 퀴즈'), findsOneWidget);
    expect(find.text(quiz.question), findsWidgets);
    expect(find.text('정답 확인'), findsOneWidget);

    await tester.tap(find.text(quiz.options[quiz.correctIndex]));
    await tester.pump();
    await tester.tap(find.text('정답 확인'));
    await tester.pumpAndSettle();

    expect(find.text(quiz.explanation), findsOneWidget);
  });

  group('홈 히어로 카드', () {
    final deadline = DateTime.now().add(const Duration(days: 6));
    final deadlineLine = '~${DateFormat('M월 d일').format(deadline)} 마감';

    Tournament heroItem({String? posterUrl}) => Tournament(
          id: 'hero-1',
          sport: 'tennis',
          title: '2026 빛고을배 전국대회 및 광주생활체육대회',
          organizer: 'QA',
          startDate: DateTime.now().add(const Duration(days: 10)),
          applicationDeadline: deadline,
          region: '광주',
          eligibleGrades: const ['open'],
          status: 'published',
          posterUrl: posterUrl,
        );

    // 테니스는 포스터가 거의 올라오지 않아 사진 자리가 빈 색면이 된다.
    // 그 자리를 없애고 마감일 정보로 대체하는 것이 이 분기의 목적.
    testWidgets('포스터가 없으면 사진 자리 대신 마감일을 보여준다', (tester) async {
      await pumpHome(
        tester,
        load: () async => [heroItem()],
        activeSport: 'tennis',
      );
      await tester.pumpAndSettle();

      expect(find.text(deadlineLine), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('포스터가 있으면 사진을 그리고 마감일 줄은 넣지 않는다', (tester) async {
      await pumpHome(
        tester,
        load: () async =>
            [heroItem(posterUrl: 'https://example.test/poster.jpg')],
        activeSport: 'tennis',
      );
      await tester.pumpAndSettle();

      final posterImages = tester.widgetList<Image>(find.byType(Image));
      expect(posterImages, isNotEmpty);
      expect(
        posterImages.every((image) => image.fit == BoxFit.cover),
        isTrue,
      );
      expect(find.text(deadlineLine), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
