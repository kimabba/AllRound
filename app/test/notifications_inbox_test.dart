import 'package:allround/models/app_notification.dart';
import 'package:allround/screens/notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final unread = AppNotification(
    id: 'unread',
    type: 'club_inquiry_received',
    title: '새 문의',
    isRead: false,
    createdAt: DateTime(2026, 7, 22),
  );
  final read = AppNotification(
    id: 'read',
    type: 'club_inquiry_reply',
    title: '문의 답변',
    isRead: true,
    createdAt: DateTime(2026, 7, 21),
  );

  test('알림함 기본 목록은 읽지 않은 알림만 표시한다', () {
    final visible = notificationsForInbox(
      [read, unread],
      showReadHistory: false,
    );

    expect(visible, [unread]);
  });

  test('지난 알림 목록은 읽은 알림만 표시한다', () {
    final visible = notificationsForInbox(
      [unread, read],
      showReadHistory: true,
    );

    expect(visible, [read]);
  });
}
