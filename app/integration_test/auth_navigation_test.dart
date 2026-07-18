import 'package:allround/main.dart' as app;
import 'package:allround/main.dart' show MatchUpApp;
import 'package:allround/testing/e2e_keys.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'
    show FlutterError, FlutterErrorDetails, NavigationBar;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _qaPassword = 'QaLocal-Only-2026!';
bool _servicesInitialized = false;

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    final exception = tester.takeException();
    if (exception != null) {
      throw TestFailure('화면 렌더링 중 오류가 발생했습니다: $exception');
    }
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('화면 요소를 제한 시간 안에 찾지 못했습니다: $finder');
}

Future<void> _launchSignedOutApp(WidgetTester tester) async {
  if (!_servicesInitialized) {
    await app.initializeAllRoundServices(
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
    _servicesInitialized = true;
  }

  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    await auth.signOut(scope: SignOutScope.local);
  }

  await tester.pumpWidget(const ProviderScope(child: MatchUpApp()));
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.loginScreen));
}

Future<void> _login(
  WidgetTester tester, {
  required String email,
}) async {
  await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AllRoundE2EKeys.emailField), email);
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordField),
    _qaPassword,
  );
  await tester.tap(find.byKey(AllRoundE2EKeys.authSubmitButton));
}

Future<String> _signUp(WidgetTester tester) async {
  final email =
      'qa-signup-${DateTime.now().microsecondsSinceEpoch}@allround.invalid';

  await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AllRoundE2EKeys.authModeToggle));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AllRoundE2EKeys.emailField), email);
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordField),
    _qaPassword,
  );
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordConfirmField),
    _qaPassword,
  );
  await tester.tap(find.byKey(AllRoundE2EKeys.authSubmitButton));
  return email;
}

Future<void> _selectMainNavigation(
  WidgetTester tester,
  Finder destination,
  int index,
) async {
  expect(destination, findsWidgets);
  final navigationBar = tester.widget<NavigationBar>(
    find.byType(NavigationBar).last,
  );
  final errors = <FlutterErrorDetails>[];
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    // web-server와 macOS integration_test 모두 NavigationDestination의 global
    // 좌표가 test root 밖으로 계산될 수 있다. 메뉴는 콜백→router→고정 screen key
    // 연결을 검증하고, 로그인·가입 폼은 별도 단계에서 실제 pointer tap을 수행한다.
    navigationBar.onDestinationSelected?.call(index);
    await tester.pump(const Duration(milliseconds: 500));
  } finally {
    FlutterError.onError = previousErrorHandler;
  }
  if (errors.isNotEmpty) {
    final messages =
        errors.map((details) => details.exceptionAsString()).join('\n---\n');
    throw TestFailure('메뉴 이동 중 오류가 발생했습니다:\n$messages');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('일반 회원이 로그인하고 주요 화면으로 라우팅한다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: 'qa-member@allround.invalid');

    await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
    expect(find.text('라운드 코치'), findsWidgets);

    await _selectMainNavigation(
      tester,
      find.byKey(AllRoundE2EKeys.navTournaments),
      1,
    );
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentsScreen));

    await _selectMainNavigation(
      tester,
      find.byKey(AllRoundE2EKeys.navClubs),
      2,
    );
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.clubsScreen));

    await _selectMainNavigation(
      tester,
      find.byKey(AllRoundE2EKeys.navMore),
      3,
    );
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.moreScreen));
    expect(find.text('어드민'), findsNothing);

    if (kIsWeb) {
      tester.element(find.byKey(AllRoundE2EKeys.moreScreen)).go('/admin');
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
      expect(find.byKey(AllRoundE2EKeys.adminScreen), findsNothing);
    }
  });

  testWidgets('미완성 계정의 앱과 웹 라우팅 차이를 지킨다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: 'qa-empty@allround.invalid');

    if (kIsWeb) {
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
      expect(find.byKey(AllRoundE2EKeys.onboardingScreen), findsNothing);
    } else {
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.onboardingScreen));
      expect(find.byKey(AllRoundE2EKeys.homeScreen), findsNothing);
    }
  });

  testWidgets('새 계정은 UI로 가입하고 일반 사용자로 시작한다', (tester) async {
    await _launchSignedOutApp(tester);
    final email = await _signUp(tester);

    if (kIsWeb) {
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
    } else {
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.onboardingScreen));
    }

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    expect(user, isNotNull);
    expect(user?.email, email);
    final profile =
        await client.from('users').select('role').eq('id', user!.id).single();
    expect(profile['role'], 'user');
  });

  if (kIsWeb) {
    testWidgets('관리자만 웹 어드민 화면에 진입한다', (tester) async {
      await _launchSignedOutApp(tester);
      await _login(tester, email: 'qa-admin@allround.invalid');

      await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
      await _selectMainNavigation(
        tester,
        find.byKey(AllRoundE2EKeys.navMore),
        3,
      );
      await _waitFor(tester, find.text('어드민'));
      await tester.tap(find.text('어드민'));
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.adminScreen));
    });
  }
}
