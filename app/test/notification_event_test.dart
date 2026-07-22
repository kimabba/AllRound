import 'dart:io';

import 'package:allround/services/notification_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('저장된 세션으로 재시작해도 FCM 리스너를 등록한다', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('AuthChangeEvent.initialSession'));
  });

  test('가입 신청 알림은 해당 클럽 관리 탭으로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 가입 신청',
        body: '가입 신청이 도착했습니다.',
        referenceType: 'club_join_request',
        referenceId: 'request-1',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1?tab=manage');
  });

  test('클럽 문의 알림은 해당 문의 대화로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 문의',
        body: '문의가 도착했습니다.',
        referenceType: 'club_inquiry:thread-1',
        referenceId: 'message-1',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1/inquiries/thread-1');
  });

  test('이동 정보가 없는 알림은 알림함으로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(title: '새 알림', body: ''),
    );

    expect(route, '/notifications');
  });
}
