import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allround/screens/tournaments/tournament_submit_screen.dart';

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
    expect(src.contains("('kta'"), isFalse, reason: '협회 코드를 화면에 나열하지 말 것');
  });

  // JY-135 codex P1-2: 부서가 0개인 협회(kssta/kasta)를 고르면 부서 칩이 하나도
  // 없어 제보를 끝낼 수 없다. 드롭다운·기본값 모두 부서가 있는 협회로 한정돼야
  // 한다. `contains('tennisOrgsWithDivisions')` 만으로는 화면 어딘가(주석·다른
  // 용처)에 그 문자열이 한 번만 있어도 통과해, 드롭다운(:160)만 몰래 다시
  // `tennisOrgs` 로 되돌려도 못 잡는다(codex P2 재지적). 필터 안 된 맨
  // `tennisOrgs` 사용이 화면에 단 한 번도 없는지를 검사한다.
  test('제보 화면은 필터 안 된 tennisOrgs 를 쓰지 않는다', () {
    final src = File('lib/screens/tournaments/tournament_submit_screen.dart')
        .readAsStringSync();
    // 설명 주석이 심볼명을 언급해 오탐이 나므로 '줄 전체가 주석' 인 줄만 걷어낸다.
    // 문자열 안의 '//'(예: 'https://...')를 자르지 않도록 줄 끝 주석은 제거하지 않는다.
    final codeOnly =
        src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    // tennisOrgsWithDivisions 는 허용, 맨 tennisOrgs 는 금지.
    final bareTennisOrgs = RegExp(r'tennisOrgs(?!WithDivisions)');
    expect(bareTennisOrgs.hasMatch(codeOnly), isFalse,
        reason: '제보 화면은 부서 있는 협회만 써야 한다(tennisOrgsWithDivisions) —'
            ' 부서 0개 협회가 선택지에 다시 노출되면 제보를 끝낼 수 없다');
  });

  // 기본 협회는 광주(gj) 고정이어야 한다 — 카탈로그 정렬 1번(kta)으로
  // 조용히 회귀하는 걸 막는다. 실제 OrgCatalog 상태와 무관하게 로직만 검증한다.
  group('defaultTennisOrgFor', () {
    test('gj 가 카탈로그에 있으면 gj 를 쓴다', () {
      expect(defaultTennisOrgFor(['kta', 'gj', 'jn']), 'gj');
    });

    test('gj 가 없으면 카탈로그 첫 항목으로 떨어진다', () {
      expect(defaultTennisOrgFor(['kta', 'jn']), 'kta');
    });

    test('카탈로그가 비어 있으면 gj 를 쓴다', () {
      expect(defaultTennisOrgFor(const []), 'gj');
    });
  });
}
