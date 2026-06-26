import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base.dart';

/// AI 채팅 SSE 스트리밍 API.
mixin ChatApi on ApiBase {
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
    String? activeSport,
    Map<String, String>? selectedEntity,
  }) async* {
    final request = http.Request('POST', uri('chat'));
    final headers = await authHeaders();
    request.headers.addAll({
      ...headers,
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'message': message,
      if (conversationId != null) 'conversation_id': conversationId,
      'enable_search': enableSearch,
      if (activeSport != null) 'active_sport': activeSport,
      if (selectedEntity != null) 'selected_entity': selectedEntity,
    });

    final client = http.Client();
    try {
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.transform(utf8.decoder).join();
        throw Exception('chat ${streamed.statusCode}: $body');
      }
      String buffer = '';
      String currentEvent = 'message';
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (true) {
          final idx = buffer.indexOf('\n\n');
          if (idx < 0) break;
          final block = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              final raw = line.substring(5).trim();
              if (raw.isEmpty) continue;
              try {
                final data = jsonDecode(raw) as Map<String, dynamic>;
                yield ChatStreamEvent(currentEvent, data);
              } catch (_) {/* skip malformed chunk */}
            }
          }
        }
      }
    } finally {
      client.close();
    }
  }
}

class ChatStreamEvent {
  final String event;
  final Map<String, dynamic> data;
  ChatStreamEvent(this.event, this.data);
}
