import 'dart:async';

import 'package:allround/services/api.dart';
import 'package:allround/state/chat_state.dart';
import 'package:allround/state/chat_stream_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stream keeps updating the shared conversation until completion',
    () async {
      final chat = ChatNotifier();
      final controller = ChatStreamController(chat);
      final events = StreamController<ChatStreamEvent>();

      final completed = controller.start(
        userMessage: '풋살 대회 알려줘',
        stream: events.stream,
      );

      events.add(
        ChatStreamEvent('meta', {'conversation_id': 'conversation-a'}),
      );
      events.add(ChatStreamEvent('delta', {'text': '서울 대회가 '}));
      events.add(ChatStreamEvent('delta', {'text': '2개 있어요.'}));
      await events.close();
      await completed;

      expect(chat.conversationId, 'conversation-a');
      expect(chat.messages.last.content, '서울 대회가 2개 있어요.');
      expect(chat.busy, isFalse);
      expect(chat.miniBarVisible, isTrue);
    },
  );

  test('stop ends only streaming and preserves received messages', () async {
    final chat = ChatNotifier();
    final controller = ChatStreamController(chat);
    final events = StreamController<ChatStreamEvent>();

    final completed = controller.start(
      userMessage: '질문',
      stream: events.stream,
    );
    events.add(ChatStreamEvent('delta', {'text': '받은 답변'}));
    await Future<void>.delayed(Duration.zero);

    controller.stop();
    await completed;

    expect(chat.busy, isFalse);
    expect(chat.messages.last.content, '받은 답변');
    expect(chat.messages, hasLength(2));
    await events.close();
  });

  test('reset cancels an active stream before clearing messages', () async {
    final chat = ChatNotifier();
    final controller = ChatStreamController(chat);
    final events = StreamController<ChatStreamEvent>();

    final completed = controller.start(
      userMessage: '질문',
      stream: events.stream,
    );
    events.add(ChatStreamEvent('delta', {'text': '받은 답변'}));
    await Future<void>.delayed(Duration.zero);

    controller.resetConversation();
    await completed;
    events.add(ChatStreamEvent('delta', {'text': '늦은 답변'}));
    await Future<void>.delayed(Duration.zero);

    expect(chat.messages, isEmpty);
    expect(chat.busy, isFalse);
    await events.close();
  });
}
