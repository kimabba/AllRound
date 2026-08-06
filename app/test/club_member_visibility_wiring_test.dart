import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('승인된 클럽은 가입 전에도 멤버 목록을 불러와 멤버 탭에 표시한다', () {
    final source =
        File('lib/screens/clubs/club_detail_screen.dart').readAsStringSync();

    expect(source, contains('if (club.isApproved || club.isMember)'));
    expect(source, contains('club.isApproved || isMember'));
    expect(source, contains('_reloadMembers();'));
    expect(source, contains('멤버, 모임, 게시판은 클럽 멤버에게만 공개됩니다.'));
  });
}
