import 'package:allround/screens/auth/verify_phone_screen.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/app_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const VerifyPhoneScreen(),
      ),
    );

AppPrimaryButton _sendButton(WidgetTester tester) =>
    tester.widget<AppPrimaryButton>(find.byKey(AllRoundE2EKeys.verifyPhoneSendButton));

void main() {
  testWidgets('AppTheme 하에서 렌더되고 코드 필드는 발송 전 숨김', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.byKey(AllRoundE2EKeys.verifyPhoneScreen), findsOneWidget);
    expect(find.byKey(AllRoundE2EKeys.verifyPhoneNumberField), findsOneWidget);
    // 발송 전에는 코드 입력/인증완료 버튼이 없다.
    expect(find.byKey(AllRoundE2EKeys.verifyPhoneCodeField), findsNothing);
    expect(find.byKey(AllRoundE2EKeys.verifyPhoneConfirmButton), findsNothing);
  });

  testWidgets('번호가 유효할 때만 인증번호 받기 버튼이 활성화', (tester) async {
    await tester.pumpWidget(_app());

    // 초기: 비활성(onPressed == null)
    expect(_sendButton(tester).onPressed, isNull);

    // 짧은 번호: 여전히 비활성
    await tester.enterText(find.byKey(AllRoundE2EKeys.verifyPhoneNumberField), '010123');
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNull);

    // 유효 번호지만 아직 동의 전: 비활성
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.verifyPhoneNumberField),
      '010-1234-5678',
    );
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNull);

    // 동의까지 하면 활성
    await tester.tap(find.byKey(AllRoundE2EKeys.verifyPhoneConsent));
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('동의를 해제하면 다시 비활성으로 돌아간다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.verifyPhoneNumberField),
      '010-1234-5678',
    );
    await tester.tap(find.byKey(AllRoundE2EKeys.verifyPhoneConsent));
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(AllRoundE2EKeys.verifyPhoneConsent));
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNull);
  });

  // 법정 고지는 "코드에 문자열이 있다"로는 부족하다. Offstage·빈 build 로도
  // 정적 검사는 통과하므로, 실제로 화면에 그려지는지를 렌더로 확인한다.
  testWidgets('수집 고지가 화면에 실제로 보인다(목적·보유기간·수탁자)', (tester) async {
    await tester.pumpWidget(_app());

    Finder visibleTextContaining(String needle) => find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains(needle),
        );

    expect(visibleTextContaining('수집·이용 및 문자 발송 위탁 동의'), findsOneWidget);
    expect(visibleTextContaining('중복 가입 방지'), findsOneWidget); // 이용 목적
    expect(visibleTextContaining('1년간 보관'), findsOneWidget); // 보유 기간
    expect(visibleTextContaining('솔라피(주)에 위탁'), findsOneWidget); // 수탁자
    expect(find.text('개인정보 처리방침'), findsOneWidget); // 원문 링크
  });
}
