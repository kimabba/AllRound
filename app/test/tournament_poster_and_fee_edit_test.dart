import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('대회 상세 포스터는 원본 비율 전체를 보여준다', () {
    final source = File(
      'lib/screens/tournaments/tournament_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('fit: BoxFit.contain'));
  });

  test('관리자는 팀당 참가비와 포스터 주소를 수정할 수 있다', () {
    final source = File(
      'lib/screens/admin/tournament_edit_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'entry_fee':"));
    expect(source, contains("'entry_fee_unit': _entryFeeUnit"));
    expect(source, contains("value: 'per_team'"));
    expect(source, contains("'poster_url':"));
  });
}
