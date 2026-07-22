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

  test('필터링 후에도 원본 순서를 보존한다', () {
    final readA = AppNotification(
      id: 'read-a',
      type: 'club_notice',
      title: '읽음 A',
      isRead: true,
      createdAt: DateTime(2026, 7, 22),
    );
    final unreadB = AppNotification(
      id: 'unread-b',
      type: 'club_notice',
      title: '안읽음 B',
      isRead: false,
      createdAt: DateTime(2026, 7, 21),
    );
    final readC = AppNotification(
      id: 'read-c',
      type: 'club_notice',
      title: '읽음 C',
      isRead: true,
      createdAt: DateTime(2026, 7, 20),
    );
    final unreadD = AppNotification(
      id: 'unread-d',
      type: 'club_notice',
      title: '안읽음 D',
      isRead: false,
      createdAt: DateTime(2026, 7, 19),
    );

    final visible = notificationsForInbox(
      [readA, unreadB, readC, unreadD],
      showReadHistory: false,
    );

    expect(visible, [unreadB, unreadD]);
  });

  test('모두 읽은 상태에서 새 알림 목록은 비어 있다', () {
    final visible = notificationsForInbox(
      [read],
      showReadHistory: false,
    );

    expect(visible, isEmpty);
  });
}
