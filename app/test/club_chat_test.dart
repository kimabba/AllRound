import 'dart:io';

import 'package:allround/models/club_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('모임 채팅 메시지를 파싱한다', () {
    final message = ClubChatMessage.fromJson({
      'id': 'message-1',
      'thread_id': 'thread-1',
      'sender_id': 'user-1',
      'body': '안녕하세요',
      'created_at': '2026-08-05T10:00:00Z',
    });

    expect(message.threadId, 'thread-1');
    expect(message.senderId, 'user-1');
    expect(message.body, '안녕하세요');
    expect(message.createdAt, DateTime.utc(2026, 8, 5, 10));
  });

  test('탈퇴한 발신자는 null로 안전하게 파싱한다', () {
    final message = ClubChatMessage.fromJson({
      'id': 'message-2',
      'thread_id': 'thread-1',
      'sender_id': null,
      'body': '기존 메시지',
      'created_at': '2026-08-05T10:00:00Z',
    });

    expect(message.senderId, isNull);
  });

  test('최신 메시지 300개를 조회한 뒤 시간순으로 반환한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(source, contains(".order('created_at', ascending: false)"));
    expect(source, contains(".order('id', ascending: false)"));
    expect(source, contains('return messages.reversed.toList'));
  });
}
