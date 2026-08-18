import 'dart:io';

import 'package:allround/router.dart' show kMobileAdminPaths;
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

  test('클럽 승인 요청 알림은 어드민 클럽 화면으로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 승인 요청',
        body: '',
        referenceType: 'club_approval_request',
      ),
    );

    expect(route, '/admin/clubs');
  });

  test('대회 알림은 해당 대회 상세로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '대회 마감 임박',
        body: '',
        referenceType: 'tournament',
        referenceId: 'tournament-1',
      ),
    );

    expect(route, '/tournaments/tournament-1');
  });

  test('대회 알림이라도 대회 ID가 공백이면 클럽 홈으로 폴스루한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '대회 알림',
        body: '',
        referenceType: 'tournament',
        referenceId: '   ',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1');
  });

  test('참조 정보 없이 클럽 ID만 있으면 클럽 홈으로 이동한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '클럽 알림',
        body: '',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1');
  });

  test('문의 알림이라도 스레드 ID가 공백이면 클럽 홈으로 폴스루한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 문의',
        body: '',
        referenceType: 'club_inquiry:   ',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1');
  });

  test('문의 알림이라도 클럽 ID가 공백이면 알림함으로 폴스루한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 문의',
        body: '',
        referenceType: 'club_inquiry:thread-1',
        clubId: '  ',
      ),
    );

    expect(route, '/notifications');
  });

  test('가입 신청 알림이라도 클럽 ID가 없으면 알림함으로 폴스루한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 가입 신청',
        body: '',
        referenceType: 'club_join_request',
      ),
    );

    expect(route, '/notifications');
  });

  test('참조 타입 앞뒤 공백은 무시하고 매칭한다', () {
    final route = routeForNotificationEvent(
      const NotificationEvent(
        title: '새 클럽 가입 신청',
        body: '',
        referenceType: ' club_join_request ',
        clubId: 'club-1',
      ),
    );

    expect(route, '/clubs/club-1?tab=manage');
  });

  // 랭킹 연결은 같은 사건인데 받는 사람이 갈린다 — 관리자는 승인 큐,
  // 신청자는 기록장. NotificationEvent 에 type 이 없어 reference_type 두 값으로
  // 가른다. 값이 어긋나면 관리자가 기록장으로, 신청자가 관리자 화면으로 간다.
  test('랭킹 연결 신청 알림은 관리자 승인 큐로 간다', () {
    expect(
      routeForNotificationEvent(
        const NotificationEvent(
          title: '랭킹 본인 연결 신청',
          body: '',
          referenceType: 'ranking_claim_request',
        ),
      ),
      '/admin/ranking-claims',
    );
  });

  test('랭킹 연결 결과 알림은 개인 기록장으로 간다', () {
    expect(
      routeForNotificationEvent(
        const NotificationEvent(
          title: '랭킹 본인 연결 완료',
          body: '',
          referenceType: 'ranking_claim_result',
        ),
      ),
      '/rankings/me',
    );
  });

  // 라우터가 /admin/* 를 모바일에서 홈으로 돌려보낸다(웹 전용). 알림이 가리키는
  // 관리자 화면이 예외 목록에 없으면, 관리자가 휴대폰에서 알림을 눌러도 홈만
  // 뜨고 아무 일도 안 일어난다 — 조용히 깨지는 종류라 목록으로 못 박는다
  // (codex 리뷰 2026-08-18).
  test('알림이 가리키는 관리자 경로는 모바일에서도 열려야 한다', () {
    const adminReferenceTypes = ['club_approval_request', 'ranking_claim_request'];
    for (final referenceType in adminReferenceTypes) {
      final route = routeForNotificationEvent(
        NotificationEvent(title: '', body: '', referenceType: referenceType),
      );
      expect(route, startsWith('/admin'), reason: referenceType);
      expect(kMobileAdminPaths, contains(route), reason: '$referenceType → $route');
    }
  });
}
