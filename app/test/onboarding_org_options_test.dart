import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// JY-136: 온보딩에서 부서가 0개인 협회(kssta/kasta)를 고르면 부서 칩이 하나도
// 뜨지 않아 selectedDivisionCodes 가 빈 채로 저장된다. 자격매칭은
// `expand_division_codes(division_codes) && eligible_grades` 배열 교집합이라
// 빈 배열이면 교집합이 항상 0 — "내 등급 대회만" 이 조용히 0건이 된다.
//
// 같은 결함을 제보 화면에서 먼저 잡았고(tournament_submit_org_options_test.dart),
// 가드(tennisOrgsWithDivisions)도 그때 만들어졌다. 온보딩만 그 가드를 통과하지
// 않아 구멍이 남아 있었다. 소스 검사로 가는 이유도 그 선례와 같다 — 선택지는
// private 메서드(_addOrg) 안에 있어 위젯을 통째로 세우지 않으면 값을 볼 수 없다.
void main() {
  test('온보딩 협회 선택지는 필터 안 된 tennisOrgs 를 쓰지 않는다', () {
    final src =
        File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
    // 설명 주석이 심볼명을 언급해 오탐이 나므로 '줄 전체가 주석' 인 줄만 걷어낸다.
    // 문자열 안의 '//'(예: 'https://...')를 자르지 않도록 줄 끝 주석은 남긴다.
    final codeOnly = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    // tennisOrgsWithDivisions 는 허용, 맨 tennisOrgs 는 금지.
    final bareTennisOrgs = RegExp(r'tennisOrgs(?!WithDivisions)');
    expect(bareTennisOrgs.hasMatch(codeOnly), isFalse,
        reason: '온보딩은 부서 있는 협회만 선택지로 내야 한다(tennisOrgsWithDivisions) —'
            ' 부서 0개 협회를 고르면 division_codes 가 빈 채로 저장돼'
            ' 자격 대회 추천이 0건이 된다');
  });
}
