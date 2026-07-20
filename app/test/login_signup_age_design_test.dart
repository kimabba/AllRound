import 'package:allround/screens/auth/login_screen.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('Google 신규 사용자는 이메일 가입 안내로 바로 이동한다', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_app(textScale: 1));

    await tester.tap(
      find.byKey(AllRoundE2EKeys.googleExistingLoginButton),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google 로그인 안내'), findsOneWidget);
    expect(find.textContaining('기존 AllRound 계정'), findsOneWidget);

    await tester.tap(find.byKey(AllRoundE2EKeys.googleEmailSignupAction));
    await tester.pumpAndSettle();
    expect(find.byKey(AllRoundE2EKeys.signupBirthDate), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({required double textScale}) {
  return ProviderScope(
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
