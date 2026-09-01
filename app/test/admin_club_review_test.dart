import 'dart:io';

import 'package:allround/models/admin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('관리자 알림 조회와 읽음 처리는 로그인한 관리자에게만 한정된다', () {
    final source =
        File('lib/services/notification_api.dart').readAsStringSync();

    expect(
        RegExp(r"\.eq\('user_id', userId\)").allMatches(source), hasLength(4));
    expect(source, contains('if (userId == null) return const [];'));
    expect(source, contains('if (userId == null) return 0;'));
  });

  test('처리 완료된 클럽은 처리자와 처리 시각을 파싱한다', () {
    final record = ClubReviewRecord.fromJson({
      'id': 'club-1',
      'name': '올라운드 클럽',
      'sport': 'tennis',
      'region': '서울',
      'address': '서울 강남구',
      'status': 'approved',
      'status_reason': null,
      'approved_by': 'admin-1',
      'approved_at': '2026-08-10T06:00:00Z',
    }, reviewerNames: const {
      'admin-1': '백과장'
    });

    expect(record.isApproved, isTrue);
    expect(record.reviewerName, '백과장');
    expect(record.reviewedAt, DateTime.utc(2026, 8, 10, 6));
  });

  test('DB에서도 관리자 전체 알림 정책을 제거한다', () {
    final migration = File(
      '../supabase/migrations/20260810070000_scope_admin_notifications_to_self.sql',
    ).readAsStringSync();

    expect(
        migration, contains('drop policy if exists notifications_admin_all'));
  });
}
