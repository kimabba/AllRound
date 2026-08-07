import 'package:allround/state/chat_state.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/widgets/mini_ballboy_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mini bar opens the same conversation and can be hidden', (
    tester,
  ) async {
    final chat = ChatNotifier()
      ..addUserMessage('질문')
      ..appendContent(1, '이어지는 답변');
    var openCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatProvider.overrideWith((ref) => chat)],
        child: MaterialApp(
          home: Scaffold(body: MiniBallboyBar(onOpen: () => openCount += 1)),
        ),
      ),
    );

    expect(find.text('이어지는 답변'), findsOneWidget);
    await tester.tap(find.byKey(AllRoundE2EKeys.miniChatOpen));
    expect(openCount, 1);

    await tester.tap(find.byKey(AllRoundE2EKeys.miniChatClose));
    await tester.pump();
    expect(chat.miniBarVisible, isFalse);
    expect(chat.messages, hasLength(2));
  });
}
