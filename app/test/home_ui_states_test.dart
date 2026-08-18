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
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
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
    expect(find.text('대회명 또는 지역을 검색해보세요'), findsOneWidget);
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

  group('홈 지역 필터', () {
    Tournament tennisAt(String id, String? region, int days) => Tournament(
          id: id,
          sport: 'tennis',
          title: '$id 대회',
          organizer: 'QA',
          startDate: DateTime.now().add(Duration(days: days)),
          region: region,
          eligibleGrades: const ['open'],
          status: 'published',
        );

    // 지역 값이 실제 데이터에서 나오는지 확인한다. 하드코딩하던 시절에는
    // 대회가 가장 많은 전남이 목록에서 빠지고 0건인 서울이 남아 있었다.
    testWidgets('지역 메뉴는 대회가 있는 지역만 건수와 함께 보여준다', (tester) async {
      await pumpHome(
        tester,
        load: () async => [
          tennisAt('jeonnam-1', '전남', 3),
          tennisAt('jeonnam-2', '전남', 5),
          tennisAt('gwangju-1', '광주', 7),
          tennisAt('national-1', null, 9),
        ],
        activeSport: 'tennis',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.location_on_outlined));
      await tester.pumpAndSettle();

      // 숫자는 그 지역을 골랐을 때 실제로 보일 개수여야 한다.
      // 전국대회 1건이 모든 지역에 함께 나오므로 지역 건수에 더해진다.
      expect(find.text('전남 3'), findsOneWidget);
      expect(find.text('광주 2'), findsOneWidget);
      expect(find.text('전국 4'), findsOneWidget);
      expect(find.text('서울'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 메뉴 숫자와 실제 목록이 어긋나면 "광주 7"을 눌렀는데 21개가 나온다.
    testWidgets('지역 메뉴 숫자는 선택 후 목록 개수와 일치한다', (tester) async {
      await pumpHome(
        tester,
        load: () async => [
          tennisAt('gwangju-1', '광주', 3),
          tennisAt('national-1', null, 5),
          tennisAt('national-2', null, 7),
        ],
        activeSport: 'tennis',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.location_on_outlined));
      await tester.pumpAndSettle();
      expect(find.text('광주 3'), findsOneWidget);

      await tester.tap(find.text('광주 3'));
      await tester.pumpAndSettle();

      // 광주 1건 + 전국대회 2건 = 3건이 목록에 나온다.
      for (final id in ['gwangju-1', 'national-1', 'national-2']) {
        expect(find.textContaining(id), findsWidgets, reason: id);
      }
      expect(tester.takeException(), isNull);
    });

    // 광주를 고른 사용자에게 광주에서 열리는 전국대회가 사라지면 안 된다.
    testWidgets('지역을 골라도 전국대회는 함께 남는다', (tester) async {
      await pumpHome(
        tester,
        load: () async => [
          tennisAt('gwangju-1', '광주', 3),
          tennisAt('national-1', null, 5),
          tennisAt('jeonnam-1', '전남', 7),
        ],
        activeSport: 'tennis',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.location_on_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('광주 2'));
      await tester.pumpAndSettle();

      expect(find.textContaining('national-1'), findsWidgets);
      expect(find.textContaining('jeonnam-1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
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

  // 겉모습만 입력창이고 실제로는 화면을 여는 버튼이다. 입력창으로 읽히면
  // 화면낭독기 사용자는 타이핑을 시도하다 아무것도 안 되는 상태에 갇힌다.
  testWidgets('홈 검색창은 화면낭독기에 버튼으로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpHome(tester, load: () async => const []);
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.bySemanticsLabel('대회 검색'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isTextField, isFalse);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  // 홈 검색은 받아둔 목록만 훑어서 "있는 대회가 안 나오는" 결과를 만들었다.
  // 이제는 서버가 전수 검색하는 전체 대회 화면의 입구다.
  testWidgets('홈 검색창을 누르면 전체 대회 검색으로 넘어간다', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/tournaments',
          builder: (_, state) => Scaffold(
            body: Text('검색 열림=${state.uri.queryParameters['search']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, __) => null,
        overrides: [
          homeTournamentsProvider.overrideWith((ref) async => const []),
          myTournamentRecordsProvider.overrideWith((ref) async => const []),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('대회명 또는 지역을 검색해보세요'));
    await tester.pumpAndSettle();

    expect(find.text('검색 열림=1'), findsOneWidget);
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

      expect(find.byType(Image), findsWidgets);
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
