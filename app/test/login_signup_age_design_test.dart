import 'dart:async';

import 'package:allround/screens/auth/login_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('이메일 가입은 320px 200% 글자에서 가입 전 생년월일을 요구한다', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(_app(textScale: 2));

    await tester.ensureVisible(
      find.byKey(AllRoundE2EKeys.emailFlowButton),
    );
    await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AllRoundE2EKeys.authModeToggle));
    await tester.pumpAndSettle();

    final birthField = find.byKey(AllRoundE2EKeys.signupBirthDate);
    expect(birthField, findsOneWidget);
    await tester.ensureVisible(birthField);
    expect(
      tester.getSize(birthField).height,
      greaterThanOrEqualTo(AppSizes.touchTarget),
    );
    expect(find.textContaining('계정 생성 전에 확인합니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google은 기존·신규 구분 없이 한 번에 계속한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    expect(find.byKey(AllRoundE2EKeys.googleContinueButton), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);
    expect(find.text('Google 로그인 안내'), findsNothing);
    expect(find.textContaining('기존 AllRound 계정'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 예전엔 Column 이 위쪽부터 채워져 큰 화면에서 아래 1/3 이 텅 비었다.
  // 화면이 커질수록 그 빈칸도 커지므로 제일 큰 화면까지 같이 본다.
  // (minHeight 에 상한을 두면 내용이 뷰포트 위쪽에 붙어 여기서 걸린다.)
  for (final size in const [Size(390, 844), Size(834, 1194)]) {
    testWidgets(
        '${size.width.toInt()}x${size.height.toInt()} 에서 CTA 가 '
        '화면 아래쪽에 자리잡는다', (tester) async {
      _setViewport(tester, size);
      await tester.pumpWidget(_app(textScale: 1));

      expect(
        tester.getBottomLeft(find.byKey(AllRoundE2EKeys.emailFlowButton)).dy,
        greaterThan(size.height * 0.85),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('소개 카드를 넘기면 다음에 할 수 있는 일이 보인다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    expect(find.textContaining('운동 친구를'), findsOneWidget);
    expect(find.textContaining('열리는 대회를'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('열리는 대회를'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('로그인 소개 슬라이드는 작은 카드가 아니라 화면 폭을 채운다', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    final pageView = find.byType(PageView);
    expect(tester.getTopLeft(pageView).dx, 0);
    expect(tester.getSize(pageView).width, 390);
    expect(find.byType(Image), findsOneWidget);
    final headline = tester.widget<Text>(
      find.text('운동 친구를 만나러 가볼까요?'),
    );
    expect(headline.maxLines, 1);
    expect(headline.style?.fontSize, greaterThan(29));
    expect(tester.takeException(), isNull);
  });

  testWidgets('사용자 소개 네 장은 서로 다른 풀스크린 사진을 사용한다', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    const expectedAssets = [
      'assets/images/auth/login-friends-v1.jpg',
      'assets/images/auth/login-futsal-tournaments-v1.jpg',
      'assets/images/auth/login-clubs-v1.jpg',
      'assets/images/auth/login-futsal-ballboy-v1.jpg',
    ];
    const expectedSports = ['TENNIS', 'FUTSAL', 'TENNIS', 'FUTSAL'];
    for (var index = 0; index < expectedAssets.length; index++) {
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, expectedAssets[index]);
      expect(find.text(expectedSports[index]), findsOneWidget);
      if (index < expectedAssets.length - 1) {
        await tester.drag(find.byType(PageView), const Offset(-360, 0));
        await tester.pumpAndSettle();
      }
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('소개 카드는 가만히 둬도 다음 장으로 넘어간다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    expect(find.textContaining('열리는 대회를'), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // 자동 넘김 타이머
    await tester.pump(const Duration(milliseconds: 500)); // 넘어가는 동안
    expect(find.textContaining('열리는 대회를'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 저절로 움직이는 화면은 멈출 방법이 있어야 한다(WCAG 2.2.2).
  testWidgets('손으로 한 번 넘기면 자동 넘김이 멈춘다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    await tester.drag(find.byType(PageView), const Offset(-360, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('열리는 대회를'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('열리는 대회를'), findsOneWidget);
    expect(find.textContaining('가까운 클럽과'), findsNothing);
  });

  testWidgets('마케팅 수신 동의는 회원가입 단계에서만 묻는다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    const consentLabel = '마케팅 정보 수신 동의 (선택)';
    expect(find.text(consentLabel), findsNothing);

    await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
    await tester.pumpAndSettle();
    expect(find.text(consentLabel), findsNothing);

    await tester.tap(find.byKey(AllRoundE2EKeys.authModeToggle));
    await tester.pumpAndSettle();
    expect(find.text(consentLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('필수 약관 동의 전에는 회원가입 버튼이 눌리지 않는다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AllRoundE2EKeys.signupTermsConsent), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(AllRoundE2EKeys.authSubmitButton))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(AllRoundE2EKeys.authModeToggle));
    await tester.pumpAndSettle();

    expect(find.text('이용약관·개인정보 처리방침 동의 (필수)'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(AllRoundE2EKeys.authSubmitButton))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(AllRoundE2EKeys.signupTermsConsent));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(AllRoundE2EKeys.authSubmitButton))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  // 모바일은 Google OAuth 콜백이 세션 변화 없이 딥링크로만 돌아와, 웹의
  // Uri.base 체크로는 못 잡는다. onAuthStateChange 스트림 에러로도 잡아내는지 확인.
  testWidgets('구글 로그인이 딥링크로 돌아오며 실패하면 모바일에서도 에러가 보인다', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final controller = StreamController<AuthState>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(textScale: 1, authStream: controller.stream));

    controller.addError(AuthException('google_signup_disabled'));
    await tester.pump();

    expect(find.text('신규 가입은 이메일로 진행해 주세요.'), findsOneWidget);
  });

  testWidgets('이메일 시트는 스크롤하면 키보드 포커스를 해제한다', (tester) async {
    _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(_app(textScale: 1));

    await tester.ensureVisible(find.byKey(AllRoundE2EKeys.emailFlowButton));
    await tester.tap(find.byKey(AllRoundE2EKeys.emailFlowButton));
    await tester.pumpAndSettle();

    final emailField = find.byKey(AllRoundE2EKeys.emailField);
    await tester.tap(emailField);
    await tester.showKeyboard(emailField);
    expect(FocusManager.instance.primaryFocus, isNotNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    // 소개 카드 안에도 스크롤뷰가 생겨 `.last` 로는 시트를 특정할 수 없다.
    await tester.drag(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(0, -120),
    );
    await tester.pump();

    expect(tester.testTextInput.isVisible, isFalse);
  });
}

Widget _app({required double textScale, Stream<AuthState>? authStream}) {
  return ProviderScope(
    overrides: [
      if (authStream != null)
        authStateProvider.overrideWith((ref) => authStream),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const LoginScreen(),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
