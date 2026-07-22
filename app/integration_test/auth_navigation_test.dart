import 'package:allround/main.dart' as app;
import 'package:allround/main.dart' show MatchUpApp;
import 'package:allround/testing/e2e_keys.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'
    show DatePickerDialog, Scrollable, Semantics, SizedBox, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _qaPassword = 'QaLocal-Only-2026!';
const _completePersonas = <String>[
  'qa-admin@allround.invalid',
  'qa-owner@allround.invalid',
  'qa-manager@allround.invalid',
  'qa-delegate@allround.invalid',
  'qa-member@allround.invalid',
  'qa-applicant@allround.invalid',
  'qa-offender@allround.invalid',
];
const _emptyPersona = 'qa-empty@allround.invalid';
const _memberPersona = 'qa-member@allround.invalid';
const _applicantPersona = 'qa-applicant@allround.invalid';
const _ownerPersona = 'qa-owner@allround.invalid';
const _memberId = '00000000-0000-4000-8000-000000000005';
const _publishedTournamentId = '00000000-0000-4000-8000-000000000101';
const _approvedClubId = '00000000-0000-4000-8000-000000000201';
const _captureDesignEvidence = bool.fromEnvironment(
  'CAPTURE_DESIGN_EVIDENCE',
);

bool _servicesInitialized = false;
late final IntegrationTestWidgetsFlutterBinding _integrationBinding;

Future<void> _captureDesignScreenshot(
  WidgetTester tester,
  String name,
) async {
  if (!kIsWeb || !_captureDesignEvidence) return;
  for (var frame = 0; frame < 2; frame += 1) {
    await tester.pump(const Duration(milliseconds: 200));
    final exception = tester.takeException();
    if (exception != null) {
      throw TestFailure('스크린샷 직전 화면 오류가 발생했습니다: $exception');
    }
  }
  await _integrationBinding.takeScreenshot(name);
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
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

Future<void> _tap(
  WidgetTester tester,
  Finder finder,
) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 350));
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

  // Each persona must start with a fresh Navigator/overlay tree. Reusing the
  // previous root can leave a successful email bottom sheet attached while the
  // router swaps back to Login, making the next synthetic account tap miss.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(const ProviderScope(child: MatchUpApp()));
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.loginScreen));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _login(
  WidgetTester tester, {
  required String email,
}) async {
  await _tap(tester, find.byKey(AllRoundE2EKeys.emailFlowButton));
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.emailField));
  await tester.enterText(find.byKey(AllRoundE2EKeys.emailField), email);
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordField),
    _qaPassword,
  );
  await _tap(tester, find.byKey(AllRoundE2EKeys.authSubmitButton));
}

Future<String> _signUp(WidgetTester tester) async {
  final email =
      'qa-signup-${DateTime.now().microsecondsSinceEpoch}@allround.invalid';

  await _tap(tester, find.byKey(AllRoundE2EKeys.emailFlowButton));
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.emailField));
  await _tap(tester, find.byKey(AllRoundE2EKeys.authModeToggle));
  await tester.enterText(find.byKey(AllRoundE2EKeys.emailField), email);
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordField),
    _qaPassword,
  );
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.passwordConfirmField),
    _qaPassword,
  );
  await _tap(tester, find.byKey(AllRoundE2EKeys.signupBirthDate));
  await _waitFor(tester, find.byType(DatePickerDialog));
  await _tap(tester, find.text('확인'));
  await _captureDesignScreenshot(tester, '18-signup-age');
  await _tap(tester, find.byKey(AllRoundE2EKeys.authSubmitButton));
  return email;
}

Future<void> _waitForSignedInLanding(
  WidgetTester tester, {
  required bool profileComplete,
}) async {
  if (!kIsWeb && !profileComplete) {
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.onboardingScreen));
    return;
  }
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
}

String _displayBirthDate(String isoDate) {
  final date = DateTime.parse(isoDate);
  return '${date.year}년 ${date.month.toString().padLeft(2, '0')}월 '
      '${date.day.toString().padLeft(2, '0')}일';
}

Future<void> _completeOnboarding(
  WidgetTester tester, {
  required String expectedBirthDate,
}) async {
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.onboardingScreen));
  await _waitFor(tester, find.text(_displayBirthDate(expectedBirthDate)));
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.onboardingNameField),
    'QA 신규 회원',
  );
  await tester.enterText(
    find.byKey(AllRoundE2EKeys.onboardingNicknameField),
    '신규QA',
  );

  await _tap(tester, find.byKey(AllRoundE2EKeys.onboardingPrimaryAction));
  await _waitFor(
    tester,
    find.byKey(AllRoundE2EKeys.onboardingRegion('seoul')),
  );
  await _tap(tester, find.byKey(AllRoundE2EKeys.onboardingRegion('seoul')));

  await _tap(tester, find.byKey(AllRoundE2EKeys.onboardingPrimaryAction));
  await _waitFor(
    tester,
    find.byKey(AllRoundE2EKeys.onboardingGrade('futsal', 'beginner')),
  );
  await _tap(
    tester,
    find.byKey(AllRoundE2EKeys.onboardingGrade('futsal', 'beginner')),
  );
  await _tap(tester, find.byKey(AllRoundE2EKeys.onboardingPrimaryAction));
  await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
}

void _goTo(WidgetTester tester, String location) {
  final anchor = find.byKey(AllRoundE2EKeys.homeScreen);
  expect(anchor, findsOneWidget);
  tester.element(anchor).go(location);
}

void _goFrom(
  WidgetTester tester,
  Finder anchor,
  String location, {
  Object? extra,
}) {
  expect(anchor, findsOneWidget);
  tester.element(anchor).go(location, extra: extra);
}

void main() {
  _integrationBinding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('합성 persona가 인증되고 각 계정 경계에 도착한다', (tester) async {
    if (kIsWeb && _captureDesignEvidence) {
      await _launchSignedOutApp(tester);
      await _tap(tester, find.byKey(AllRoundE2EKeys.emailFlowButton));
      await _tap(tester, find.byKey(AllRoundE2EKeys.authSubmitButton));
      await _captureDesignScreenshot(tester, '09-login-error');
    }

    final completePersonas =
        kIsWeb ? _completePersonas : const ['qa-member@allround.invalid'];
    for (final email in completePersonas) {
      await _launchSignedOutApp(tester);
      await _login(tester, email: email);
      await _waitForSignedInLanding(tester, profileComplete: true);
      expect(Supabase.instance.client.auth.currentUser?.email, email);
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    }

    await _launchSignedOutApp(tester);
    await _login(tester, email: _emptyPersona);
    await _waitForSignedInLanding(tester, profileComplete: false);
    expect(Supabase.instance.client.auth.currentUser?.email, _emptyPersona);
    if (kIsWeb) {
      expect(find.byKey(AllRoundE2EKeys.onboardingScreen), findsNothing);
    } else {
      expect(find.byKey(AllRoundE2EKeys.homeScreen), findsNothing);
    }
  });

  testWidgets('일반 회원의 4탭과 전역 채팅·전체화면 draft를 잇는다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: 'qa-member@allround.invalid');
    await _waitForSignedInLanding(tester, profileComplete: true);
    await _waitFor(
      tester,
      find.byKey(AllRoundE2EKeys.homeTournamentList),
      timeout: const Duration(seconds: 35),
    );
    await _captureDesignScreenshot(tester, '01-home');

    await _tap(tester, find.byKey(AllRoundE2EKeys.navTournaments));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentsScreen));
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    await _captureDesignScreenshot(tester, '02-tournaments');

    await _tap(tester, find.byKey(AllRoundE2EKeys.navClubs));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.clubsScreen));
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    await _captureDesignScreenshot(tester, '03-clubs');

    await _tap(tester, find.byKey(AllRoundE2EKeys.navProfile));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.profileScreen));
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);

    await _tap(tester, find.byKey(AllRoundE2EKeys.navToday));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));

    await _tap(tester, find.byKey(AllRoundE2EKeys.globalChatDock));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.embeddedChatSheet));
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.chatInput),
      'QA 전역 채팅 draft',
    );
    await _tap(tester, find.byKey(AllRoundE2EKeys.chatExpandButton));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.fullChatScreen));
    await tester.pump(const Duration(milliseconds: 500));

    final input = tester.widget<TextField>(
      find.byKey(AllRoundE2EKeys.chatInput).last,
    );
    expect(input.controller?.text, 'QA 전역 채팅 draft');
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsNothing);
    await _captureDesignScreenshot(tester, '10-full-chat');

    if (!kIsWeb || _captureDesignEvidence) {
      _goFrom(tester, find.byKey(AllRoundE2EKeys.fullChatScreen), '/more');
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.moreScreen));
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '11-more');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.moreScreen),
        '/notifications',
      );
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.notificationsScreen));
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.notificationsReady));
      expect(find.text('QA 회원 알림'), findsOneWidget);
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '12-notifications');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.notificationsScreen),
        '/favorites',
      );
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.favoritesScreen));
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.favoritesReady));
      expect(find.text('QA 광주 일반부 공개대회'), findsOneWidget);
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '13-favorites');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.favoritesScreen),
        '/profile',
      );
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.profileScreen));
      await tester.scrollUntilVisible(
        find.byKey(AllRoundE2EKeys.profileAppearanceSection),
        320,
        scrollable: find
            .descendant(
              of: find.byKey(AllRoundE2EKeys.profileScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 12,
      );
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '14-profile-settings');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.profileScreen),
        '/rules',
      );
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.rulesScreen));
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.rulesReady));
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '15-rules');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.rulesScreen),
        '/blocked-users',
      );
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.blockedUsersScreen));
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.blockedUsersReady));
      expect(find.text('QA 제재대상'), findsOneWidget);
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '16-blocked-users');

      _goFrom(
        tester,
        find.byKey(AllRoundE2EKeys.blockedUsersScreen),
        '/tournaments/submit',
      );
      await _waitFor(
        tester,
        find.byKey(AllRoundE2EKeys.tournamentSubmitScreen),
      );
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
      await _captureDesignScreenshot(tester, '17-tournament-submit');
    }
  });

  testWidgets('대회 목록에서 상세와 명시적 AI 문맥 연결까지 이어진다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: _memberPersona);
    await _waitForSignedInLanding(tester, profileComplete: true);

    await _tap(tester, find.byKey(AllRoundE2EKeys.navTournaments));
    await _waitFor(
      tester,
      find.byKey(AllRoundE2EKeys.tournamentCard('preview-tennis-1')),
    );
    await _tap(
      tester,
      find.byKey(AllRoundE2EKeys.tournamentCard('preview-tennis-1')),
    );
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentDetailScreen));
    expect(
      find.descendant(
        of: find.byKey(AllRoundE2EKeys.tournamentDetailScreen),
        matching: find.text('광주 오픈 테니스 챌린지'),
      ),
      findsOneWidget,
    );
    await _captureDesignScreenshot(tester, '04-tournament-detail');
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);

    await _tap(tester, find.byKey(AllRoundE2EKeys.globalChatDock));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.embeddedChatSheet));
    expect(find.byKey(AllRoundE2EKeys.chatContextDetached), findsOneWidget);
    await _tap(tester, find.byKey(AllRoundE2EKeys.chatContextDetached));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.chatContextAttached));
    await _captureDesignScreenshot(tester, '05-context-chat');
  });

  testWidgets('관심 대회 저장을 왕복하고 MY 기록에서 다시 확인한다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: _memberPersona);
    await _waitForSignedInLanding(tester, profileComplete: true);

    _goTo(tester, '/tournaments/$_publishedTournamentId');
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentDetailScreen));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentFavoriteSaved));
    expect(
      find.descendant(
        of: find.byKey(AllRoundE2EKeys.tournamentDetailScreen),
        matching: find.text('QA 광주 일반부 공개대회'),
      ),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(AllRoundE2EKeys.tournamentFavoriteSaved));
    await _waitFor(
      tester,
      find.byKey(AllRoundE2EKeys.tournamentFavoriteUnsaved),
    );
    final client = Supabase.instance.client;
    final removedFavorite = await client
        .from('tournament_favorites')
        .select('tournament_id')
        .eq('user_id', _memberId)
        .eq('tournament_id', _publishedTournamentId)
        .maybeSingle();
    expect(removedFavorite, isNull);

    await _tap(tester, find.byKey(AllRoundE2EKeys.tournamentFavoriteUnsaved));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.tournamentFavoriteSaved));
    final restoredFavorite = await client
        .from('tournament_favorites')
        .select('tournament_id')
        .eq('user_id', _memberId)
        .eq('tournament_id', _publishedTournamentId)
        .maybeSingle();
    expect(restoredFavorite?['tournament_id'], _publishedTournamentId);

    _goFrom(
      tester,
      find.byKey(AllRoundE2EKeys.tournamentDetailScreen),
      '/profile',
    );
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.profileScreen));
    await _waitFor(tester, find.text('qa_member'));
    final profileTournament = find.descendant(
      of: find.byKey(AllRoundE2EKeys.profileScreen),
      matching: find.text('QA 광주 일반부 공개대회'),
    );
    await tester.scrollUntilVisible(
      profileTournament,
      220,
      scrollable: find
          .descendant(
            of: find.byKey(AllRoundE2EKeys.profileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 12,
    );
    expect(profileTournament, findsOneWidget);
    await _captureDesignScreenshot(tester, '06-profile-records');
  });

  testWidgets('클럽 신청자와 운영자가 각자 허용된 상태만 본다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: _applicantPersona);
    await _waitForSignedInLanding(tester, profileComplete: true);

    _goTo(tester, '/clubs/$_approvedClubId');
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.clubDetailScreen));
    await tester.scrollUntilVisible(
      find.byKey(AllRoundE2EKeys.clubJoinPendingAction),
      220,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 12,
    );
    expect(find.byKey(AllRoundE2EKeys.clubJoinPendingAction), findsOneWidget);
    expect(find.byKey(AllRoundE2EKeys.clubManagementTab), findsNothing);
    await _captureDesignScreenshot(tester, '07-club-applicant');

    await _launchSignedOutApp(tester);
    await _login(tester, email: _ownerPersona);
    await _waitForSignedInLanding(tester, profileComplete: true);

    _goTo(tester, '/clubs/$_approvedClubId');
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.clubDetailScreen));
    await _tap(tester, find.byKey(AllRoundE2EKeys.clubManagementTab));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.clubManagementContent));
    expect(find.text('운영 권한'), findsOneWidget);
    expect(find.byKey(AllRoundE2EKeys.clubJoinPendingAction), findsNothing);
    await _captureDesignScreenshot(tester, '08-club-management');

    await _tap(tester, find.byKey(AllRoundE2EKeys.globalChatDock));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.embeddedChatSheet));
    await _tap(tester, find.byKey(AllRoundE2EKeys.chatContextDetached));
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.chatContextAttached));
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.chatInput),
      '이 클럽 정보를 알려줘',
    );
    await _tap(tester, find.byTooltip('메시지 보내기'));
    await _waitFor(
      tester,
      find.byKey(AllRoundE2EKeys.latestAssistantMessage),
      timeout: const Duration(seconds: 30),
    );
    final answer = tester.widget<Semantics>(
      find.byKey(AllRoundE2EKeys.latestAssistantMessage),
    );
    expect(answer.properties.label, contains('실제 회원과 무관한 QA 전용 클럽'));
  });

  testWidgets('일반 회원의 관리자 직접 진입을 서버 역할 기준으로 차단한다', (tester) async {
    await _launchSignedOutApp(tester);
    await _login(tester, email: 'qa-member@allround.invalid');
    await _waitForSignedInLanding(tester, profileComplete: true);

    _goTo(tester, '/admin');
    await _waitFor(tester, find.byKey(AllRoundE2EKeys.homeScreen));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(AllRoundE2EKeys.adminScreen), findsNothing);
  });

  if (kIsWeb) {
    testWidgets('관리자 persona만 웹 관리자 화면에 진입한다', (tester) async {
      await _launchSignedOutApp(tester);
      await _login(tester, email: 'qa-admin@allround.invalid');
      await _waitForSignedInLanding(tester, profileComplete: true);

      _goTo(tester, '/admin');
      await _waitFor(tester, find.byKey(AllRoundE2EKeys.adminScreen));
    });
  }

  testWidgets('새 계정은 UI로 가입하고 일반 사용자로 시작한다', (tester) async {
    await _launchSignedOutApp(tester);
    final email = await _signUp(tester);
    await _waitForSignedInLanding(tester, profileComplete: false);

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    expect(user, isNotNull);
    expect(user?.email, email);

    final profile = await client
        .from('users')
        .select('role,birth_date')
        .eq('id', user!.id)
        .single();
    expect(profile['role'], 'user');
    expect(profile['birth_date'], isA<String>());
    final preverifiedBirthDate = profile['birth_date'] as String;

    if (!kIsWeb) {
      await _completeOnboarding(
        tester,
        expectedBirthDate: preverifiedBirthDate,
      );

      final completedProfile = await client
          .from('users')
          .select('name,nickname,birth_date')
          .eq('id', user.id)
          .single();
      expect(completedProfile['name'], 'QA 신규 회원');
      expect(completedProfile['nickname'], '신규QA');
      expect(completedProfile['birth_date'], isNotNull);

      final sports = await client
          .from('user_sports')
          .select('sport,grade,is_primary')
          .eq('user_id', user.id);
      expect(sports, [
        {'sport': 'futsal', 'grade': 'beginner', 'is_primary': true},
      ]);
      expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    }
  });
}
