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
  });
}
