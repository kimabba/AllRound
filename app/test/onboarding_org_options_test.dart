import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allround/screens/auth/onboarding_screen.dart';

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

  // 위 소스 검사만으로는 절반만 막힌다. 부서가 있는 협회를 골라도 칩을 하나도
  // 누르지 않으면 똑같이 division_codes 가 빈 채로 저장된다 — 실제로 프로덕션에
  // 남아 있는 깨진 행(org=kata, division='default', division_codes=[])이
  // 이 경로에서 나왔다. kata 는 부서가 6개 있는 협회다.
  group('tennisOrgSelectionsAreComplete', () {
    test('협회가 없으면 통과한다 (테니스 미등록·협회 미추가)', () {
      expect(tennisOrgSelectionsAreComplete(const []), isTrue);
    });

    test('모든 협회가 부서를 1개 이상 골랐으면 통과한다', () {
      expect(
        tennisOrgSelectionsAreComplete([
          {'gj_m_open'},
          {'kata_1', 'kata_2'},
        ]),
        isTrue,
      );
    });

    test('한 협회라도 부서가 비면 막는다', () {
      expect(
        tennisOrgSelectionsAreComplete([
          {'gj_m_open'},
          <String>{},
        ]),
        isFalse,
      );
    });

    test('협회 하나가 통째로 비어도 막는다', () {
      expect(tennisOrgSelectionsAreComplete([<String>{}]), isFalse);
    });

    // 위 4개는 함수의 진리표만 본다 — 함수가 _canSubmit 에서 떨어져 나가면
    // 전부 통과하면서 게이트만 사라진다(codex #3). 연결 자체를 못으로 박는다.
    // #337: saveTennisOrgs 는 delete-all + insert 라 화면이 보낸 목록이 곧
    // 전부가 된다. 화면이 기존 협회를 복원하지 않으면, 재진입해 협회를 하나
    // 추가하는 순간 나머지가 사라진다. 위 선례와 같은 이유로 소스 검사다 —
    // 복원 결과는 private 상태(_orgs)에만 남는다.
    test('재진입 시 기존 협회를 불러온다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      expect(
          src, contains('_prepareExistingOrgs(ref.watch(userTennisOrgsProvider'),
          reason: 'build 가 등록된 협회를 프리로드해야 한다 —'
              ' 안 하면 재진입 저장이 기존 협회를 통째로 지운다(#337)');
    });

    test('협회 저장은 복원이 끝난 뒤에만 한다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      final guard =
          RegExp(r'if \(_tennisRegistered && ([^)]*)\) \{').firstMatch(src);
      expect(guard, isNotNull, reason: '협회 저장 가드를 찾지 못했다');
      expect(guard!.group(1), '_existingOrgsReady',
          reason: '복원 전에는 저장을 막아야 한다 — 아직 빈 _orgs 를 보내면'
              ' delete-all 로 기존 협회가 사라진다(#337).'
              ' _orgs.isNotEmpty 가드는 반대로 협회 전체 삭제를 불가능하게 만든다');
    });

    test('_canSubmit 에 연결돼 있다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      // 첫 세미콜론에서 끊는다. `;\n` 까지 늘리면 줄끝 주석이 붙은 순간
      // 매치가 다음 getter 까지 삼켜, 연결을 끊어도 통과한다(변이 검증에서 확인).
      final canSubmit =
          RegExp(r'bool get _canSubmit =>([^;]*);').firstMatch(src);
      expect(canSubmit, isNotNull, reason: '_canSubmit getter 를 찾지 못했다');
      expect(canSubmit!.group(1), contains('tennisOrgSelectionsAreComplete'),
          reason: '_canSubmit 이 부서 선택 검사를 통과해야 한다 —'
              ' 연결이 끊기면 부서 미선택 저장이 다시 열린다');
    });
  });
}
