import 'package:flutter_test/flutter_test.dart';

import 'package:allround/models/tournament.dart';

void main() {
  test('클럽장이 삭제한 클럽은 소프트 삭제 상태로 판별한다', () {
    final club = Club.fromJson({
      'id': 'deleted-club',
      'sport': 'futsal',
      'name': '삭제한 테스트 클럽',
      'status': 'rejected',
      'status_reason': 'deleted_by_owner',
    });

    expect(club.isDeletedByOwner, isTrue);
  });

  test('일반 반려 클럽은 삭제된 클럽으로 판별하지 않는다', () {
    final club = Club.fromJson({
      'id': 'rejected-club',
      'sport': 'tennis',
      'name': '수정 가능한 반려 클럽',
      'status': 'rejected',
      'status_reason': '활동 지역을 더 자세히 적어주세요.',
    });

    expect(club.isDeletedByOwner, isFalse);
  });
}
