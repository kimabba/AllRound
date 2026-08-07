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
  bool miniBarVisible = false;

  void setDraft(String text) {
    draft = text;
  }

  void addUserMessage(String text) {
    messages.add(ChatMessage(role: 'user', content: text));
    messages.add(ChatMessage(role: 'assistant', content: ''));
    busy = true;
    miniBarVisible = true;
    notifyListeners();
  }

  bool get hasConversation => messages.isNotEmpty;

  String get miniBarPreview {
    final assistantMessages = messages.reversed.where(
      (message) => message.role == 'assistant',
    );
    final content =
        assistantMessages.isEmpty ? '' : assistantMessages.first.content.trim();
    if (busy && content.isEmpty) {
      return '답변을 작성하고 있어요…';
    }
    if (content.isEmpty) {
      return '볼보이에게 질문을 보냈어요.';
    }
    return content
        .replaceAll(RegExp(r'[\n\r]+'), ' ')
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  void showMiniBar() {
    if (!hasConversation || miniBarVisible) return;
    miniBarVisible = true;
    notifyListeners();
  }

  void hideMiniBar() {
    if (!miniBarVisible) return;
    miniBarVisible = false;
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
    miniBarVisible = false;
    notifyListeners();
  }
}

final chatProvider = ChangeNotifierProvider<ChatNotifier>((ref) {
  return ChatNotifier();
});
