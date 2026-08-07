import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_ui.dart';
import '../services/api.dart';
import 'chat_state.dart';

/// 채팅 화면이 닫혀도 SSE 답변을 끝까지 받는 전역 스트리밍 컨트롤러.
/// 화면은 요청을 시작할 뿐이며 구독 생명주기는 이 객체가 소유한다.
class ChatStreamController {
  ChatStreamController(this._chat);

  static const _firstByteTimeout = Duration(seconds: 15);

  final ChatNotifier _chat;
  StreamSubscription<ChatStreamEvent>? _subscription;
  Completer<void>? _activeCompleter;
  int _requestId = 0;

  Future<void> start({
    required String userMessage,
    required Stream<ChatStreamEvent> stream,
  }) {
    if (userMessage.trim().isEmpty || _chat.busy) {
      return Future<void>.value();
    }

    _cancelSubscription();
    _chat.addUserMessage(userMessage.trim());
    final assistantIndex = _chat.lastAssistantIndex;
    final requestId = ++_requestId;
    final completer = Completer<void>();
    _activeCompleter = completer;

    _subscription = stream.timeout(
      _firstByteTimeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException('응답 대기 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.'),
        );
        sink.close();
      },
    ).listen(
      (event) => _handleEvent(event, assistantIndex),
      onError: (Object error) {
        if (requestId != _requestId) return;
        _chat.appendContent(
          assistantIndex,
          '\n\n[연결 실패] ${formatChatError(error)}',
        );
      },
      onDone: () => _finish(requestId, completer),
    );

    return completer.future;
  }

  void stop() {
    final completer = _activeCompleter;
    _requestId += 1;
    _cancelSubscription();
    _chat.finishStreaming();
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeCompleter = null;
  }

  /// 인증 전환이나 사용자의 초기화 요청에서는 구독을 먼저 끊어야 한다.
  /// 그렇지 않으면 늦게 도착한 delta가 비워진 메시지 인덱스를 갱신할 수 있다.
  void resetConversation() {
    stop();
    _chat.reset();
  }

  void dispose() {
    final completer = _activeCompleter;
    _requestId += 1;
    _cancelSubscription();
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _activeCompleter = null;
  }

  void _handleEvent(ChatStreamEvent event, int assistantIndex) {
    switch (event.event) {
      case 'meta':
        _chat.setConversationId(event.data['conversation_id'] as String?);
      case 'delta':
        _chat.appendContent(
          assistantIndex,
          event.data['text'] as String? ?? '',
        );
      case 'citation':
        _chat.setCitations(assistantIndex, _mapList(event.data['items']));
      case 'ui':
        final blocks = ChatUiBlock.listFromEvent(event.data);
        if (blocks.isNotEmpty) {
          _chat.addUiBlocks(assistantIndex, blocks);
        }
      case 'error':
        _chat.appendContent(
          assistantIndex,
          '\n\n[오류] ${formatChatError(event.data['message'])}',
        );
    }
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _finish(int requestId, Completer<void> completer) {
    if (requestId != _requestId) return;
    _subscription = null;
    _activeCompleter = null;
    _chat.finishStreaming();
    if (!completer.isCompleted) completer.complete();
  }

  void _cancelSubscription() {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}

String formatChatError(Object? error) {
  final text = error?.toString() ?? '';
  if (text.contains('API_KEY_INVALID') ||
      text.contains('API key not valid') ||
      text.contains('GEMINI_API_KEY')) {
    return 'AI 코치를 일시적으로 이용할 수 없어요. 잠시 후 다시 시도해 주세요.';
  }
  if (text.contains('401') || text.contains('JWT')) {
    return '로그인 세션을 확인할 수 없습니다. 다시 로그인한 뒤 시도해 주세요.';
  }
  if (text.contains('rate limit') || text.contains('429')) {
    return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
  }
  return '챗봇 응답을 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.';
}

final chatStreamControllerProvider = Provider<ChatStreamController>((ref) {
  final controller = ChatStreamController(ref.read(chatProvider));
  ref.onDispose(controller.dispose);
  return controller;
});
