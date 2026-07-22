import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('운영진 가입 신청 목록은 권한 검증 Edge Function을 사용한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(
      source,
      contains("uri('clubs-review-join', {'club_id': clubId})"),
    );
    expect(source, isNot(contains('users(name, email)')));
  });
}
