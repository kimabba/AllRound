import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('모임 일정 등록과 종료·삭제는 권한 검증 Edge Function을 사용한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(source, contains("uri('clubs-events')"));
    expect(source, contains("'action': action"));
    expect(source, isNot(contains(".from('club_events').insert")));
  });

  test('조기 종료된 일정도 목록에 남겨 상태를 표시한다', () {
    final source = File('lib/services/club_api.dart').readAsStringSync();

    expect(source, isNot(contains(".isFilter('ended_early_at', null)")));
    expect(source,
        contains(".select('*, club_event_attendees(user_id, status)')"));
  });
}
