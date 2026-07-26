import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 제보 화면이 별도 협회 목록을 갖고 있으면, 협회를 DB 에 추가해도 이 화면에서만
// 조용히 누락된다(JY-135). 소스를 직접 읽어 두 번째 목록의 부활을 막는다.
//
// 소스 검사로 가는 이유: 목록이 private const 라 위젯을 띄우지 않고는 값을 볼 수
// 없는데, 위젯 테스트는 이 화면의 폼·프로바이더를 통째로 세워야 해 비용이 크다.
// 같은 저장소의 catalog_rebuild_test.dart:74-91 이 router.dart 를 파싱해 규칙을
// 강제하는 선례를 따른다.
void main() {
  test('제보 화면에 협회 하드코딩 목록이 없다', () {
    final src = File('lib/screens/tournaments/tournament_submit_screen.dart')
        .readAsStringSync();
    expect(src.contains('_tennisOrgOptions'), isFalse,
        reason: '협회 선택지는 OrgCatalog(tennisOrgs)를 써야 한다');
    // 코드 리터럴을 나열한 별도 목록이 되살아나는 것도 막는다.
    expect(src.contains("('kta'"), isFalse,
        reason: '협회 코드를 화면에 나열하지 말 것');
  });
}
