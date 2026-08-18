import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('클럽 단체 대화와 1:1 대화 진입점이 멤버에게 제공된다', () {
    final source = File(
      'lib/screens/clubs/club_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("tooltip: '멤버 단체 채팅'"));
    expect(source, contains('if (isMember && !widget.adminPreview)'));
    expect(source, contains('onPressed: _openMemberGroupChat'));
    expect(source, contains("label: const Text('1:1 채팅')"));
    expect(source, contains('otherMember: member'));
  });
}
