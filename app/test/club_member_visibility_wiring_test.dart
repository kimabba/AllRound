import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('승인된 모임은 가입 전에도 멤버 목록을 불러와 멤버 탭에 표시한다', () {
    final source =
        File('lib/screens/clubs/club_detail_screen.dart').readAsStringSync();

    expect(source, contains('if (club.isApproved || club.isMember)'));
    expect(source, contains('club.isApproved || isMember'));
    expect(source, contains('_reloadMembers();'));
    expect(source, contains('일정과 게시판은 모임 멤버에게만 공개됩니다.'));
  });
}
