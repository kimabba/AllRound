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

  // 법정 고지는 "코드에 문자열이 있다"로는 부족하다. 위젯 트리에 존재하는지만 보면
  // Offstage·Opacity(0)·화면 밖 배치로 전부 우회된다. 그래서 여기서는
  // ① 트리에 있고 ② 렌더 크기가 0 이 아니며 ③ 화면 안에 들어와 있고
  // ④ 숨김 위젯에 감싸여 있지 않은지까지 확인한다.
  testWidgets('수집 고지가 화면에 실제로 보인다(목적·보유기간·수탁자)', (tester) async {
    await tester.pumpWidget(_app());

    final screen = tester.getSize(find.byKey(AllRoundE2EKeys.verifyPhoneScreen));

    void expectActuallyVisible(String needle) {
      final finder = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains(needle),
        description: 'Text containing "$needle"',
      );
      expect(finder, findsOneWidget, reason: '"$needle" 고지가 트리에 없다');

      // 크기가 0 이면 그려져도 보이지 않는다.
      final size = tester.getSize(finder);
      expect(size.width, greaterThan(0), reason: '"$needle" 의 폭이 0 이다');
      expect(size.height, greaterThan(0), reason: '"$needle" 의 높이가 0 이다');

      // 화면 밖으로 밀어낸 경우를 막는다. 아래·오른쪽뿐 아니라 위·왼쪽으로 밀어낸
      // 경우도 봐야 한다(음수 좌표로 완전히 벗어나도 크기는 0 이 아니다).
      final topLeft = tester.getTopLeft(finder);
      final bottomRight = tester.getBottomRight(finder);
      expect(topLeft.dy, lessThan(screen.height), reason: '"$needle" 이 화면 아래로 벗어났다');
      expect(topLeft.dx, lessThan(screen.width), reason: '"$needle" 이 화면 오른쪽으로 벗어났다');
      expect(bottomRight.dy, greaterThan(0), reason: '"$needle" 이 화면 위로 벗어났다');
      expect(bottomRight.dx, greaterThan(0), reason: '"$needle" 이 화면 왼쪽으로 벗어났다');

      // Offstage / Opacity(0) / Visibility(false) 로 감싸 숨기는 경로를 막는다.
      // Scaffold 내부도 Offstage 를 쓰므로 실제로 숨긴 것(offstage: true)만 본다.
      final offstage = tester
          .widgetList<Offstage>(find.ancestor(of: finder, matching: find.byType(Offstage)))
          .where((o) => o.offstage);
      expect(offstage, isEmpty, reason: '"$needle" 이 Offstage 안에 있다');
      final faded = tester
          .widgetList<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)))
          .where((o) => o.opacity == 0);
      expect(faded, isEmpty, reason: '"$needle" 이 Opacity(0) 안에 있다');
      final hidden = tester
          .widgetList<Visibility>(find.ancestor(of: finder, matching: find.byType(Visibility)))
          .where((v) => !v.visible);
      expect(hidden, isEmpty, reason: '"$needle" 이 Visibility(false) 안에 있다');
    }

    expectActuallyVisible('수집·이용 및 문자 발송 위탁 동의'); // 동의 항목
    expectActuallyVisible('중복 가입 방지'); // 이용 목적
    expectActuallyVisible('1년간 보관'); // 보유 기간
    expectActuallyVisible('솔라피(주)에 위탁'); // 수탁자
    expectActuallyVisible('개인정보 처리방침'); // 원문 링크
  });
}
