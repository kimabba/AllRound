import 'package:allround/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat reset clears messages, conversation id, and unsent draft', () {
    final chat = ChatNotifier()
      ..setDraft('private unsent draft')
      ..setConversationId('conversation-a')
      ..addUserMessage('private message');

    chat.reset();

    expect(chat.messages, isEmpty);
    expect(chat.conversationId, isNull);
    expect(chat.draft, isEmpty);
    expect(chat.busy, isFalse);
    expect(chat.miniBarVisible, isFalse);
  });

  test('new message opens mini bar and closing it keeps the conversation', () {
    final chat = ChatNotifier()..addUserMessage('서울 풋살 대회를 알려줘');

    expect(chat.miniBarVisible, isTrue);
    expect(chat.miniBarPreview, '답변을 작성하고 있어요…');

    chat.appendContent(chat.lastAssistantIndex, '이번 주 대회는 2개예요.');
    chat.finishStreaming();
    chat.hideMiniBar();

    expect(chat.miniBarVisible, isFalse);
    expect(chat.messages, hasLength(2));
    expect(chat.miniBarPreview, '이번 주 대회는 2개예요.');

    chat.showMiniBar();
    expect(chat.miniBarVisible, isTrue);
  });
}
