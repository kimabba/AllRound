import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/chat_ui.dart';

class ChatMessage {
  final String role;
  String content;
  List<Map<String, dynamic>> citations;
  List<ChatUiBlock> uiBlocks;

  ChatMessage({required this.role, required this.content})
      : citations = <Map<String, dynamic>>[],
        uiBlocks = <ChatUiBlock>[];
}

class ChatNotifier extends ChangeNotifier {
  final List<ChatMessage> messages = [];
  String? conversationId;
  String draft = '';
  bool busy = false;

  void setDraft(String text) {
    draft = text;
  }

  void addUserMessage(String text) {
    messages.add(ChatMessage(role: 'user', content: text));
    messages.add(ChatMessage(role: 'assistant', content: ''));
    busy = true;
    notifyListeners();
  }

  int get lastAssistantIndex => messages.length - 1;

  void appendContent(int index, String text) {
    messages[index].content += text;
    notifyListeners();
  }

  void setCitations(int index, List<Map<String, dynamic>> items) {
    messages[index].citations = [
      ...messages[index].citations,
      ...items,
    ];
    notifyListeners();
  }

  void addUiBlocks(int index, List<ChatUiBlock> blocks) {
    messages[index].uiBlocks = [
      ...messages[index].uiBlocks,
      ...blocks,
    ];
    notifyListeners();
  }

  void setConversationId(String? id) {
    conversationId = id;
  }

  void finishStreaming() {
    busy = false;
    notifyListeners();
  }

  void reset() {
    messages.clear();
    conversationId = null;
    draft = '';
    busy = false;
    notifyListeners();
  }
}

final chatProvider = ChangeNotifierProvider<ChatNotifier>((ref) {
  return ChatNotifier();
});
