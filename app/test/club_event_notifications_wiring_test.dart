import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('클럽 일정 등록과 종료·삭제는 권한 검증 Edge Function을 사용한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(source, contains("uri('clubs-events')"));
    expect(source, contains("'action': action"));
    expect(source, isNot(contains(".from('club_events').insert")));
  });

  test('클럽 일정 목록은 조기 종료된 일정을 제외한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(source, contains(".isFilter('ended_early_at', null)"));
  });
}
