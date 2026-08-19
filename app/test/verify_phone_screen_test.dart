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

    // 유효 번호: 활성
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.verifyPhoneNumberField),
      '010-1234-5678',
    );
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNotNull);
  });
}
