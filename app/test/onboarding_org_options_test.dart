import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allround/models/tournament.dart';
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
    // 금지 대상은 '맨' tennisOrgs 다. tennisOrgsWithDivisions 처럼 이름이
    // 이어지는 다른 심볼은 별개이므로, 뒤에 식별자 문자가 오면 제외한다
    // (WithDivisions 만 예외로 두면 새 심볼이 생길 때마다 오탐이 난다).
    final bareTennisOrgs = RegExp(r'tennisOrgs(?![A-Za-z0-9_])');
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

    test('복원이 끝나기 전에는 제출 자체를 막는다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      expect(src, contains('if (_tennisRegistered && !_existingOrgsReady) {'),
          reason: '복원 전 제출은 이유를 보여주고 중단해야 한다 — 그냥 저장하면'
              ' 빈 _orgs 가 delete-all 로 기존 협회를 지우고(#337),'
              ' 조용히 건너뛰면 이번에 고른 협회가 안내 없이 사라진다');
      // 저장 블록에 _orgs.isNotEmpty 가드가 되살아나면 협회 전체 삭제가
      // 다시 불가능해진다(사용자가 다 지워도 서버엔 남는다).
      expect(src, isNot(contains('_tennisRegistered && _orgs.isNotEmpty')),
          reason: '협회를 전부 지운 저장도 그대로 보내야 한다');
    });

    // 복원이 늦게 도착하는 사이 사용자가 협회를 먼저 추가할 수 있다. 그때
    // 복원을 통째로 건너뛰면 서버 협회가 저장 목록에서 빠져 delete-all 에
    // 지워진다 — 고치려던 유실이 그대로 재발한다(codex #1).
    group('tennisOrgsMissingFromDraft', () {
      UserTennisOrg org(String code) =>
          UserTennisOrg(org: code, division: 'default');

      test('화면에 없는 서버 협회만 고른다', () {
        final missing =
            tennisOrgsMissingFromDraft([org('gj'), org('kta')], {'gj'});
        expect(missing.map((o) => o.org), ['kta']);
      });

      test('사용자가 먼저 고른 협회는 중복으로 넣지 않는다', () {
        expect(tennisOrgsMissingFromDraft([org('gj')], {'gj'}), isEmpty);
      });

      test('초안이 비어 있으면 서버 목록을 전부 복원한다', () {
        final missing =
            tennisOrgsMissingFromDraft([org('gj'), org('kta')], <String>{});
        expect(missing.map((o) => o.org), ['gj', 'kta']);
      });
    });

    // 협회 선택 시트는 열릴 때의 스냅샷으로 선택지를 만든다. 그 사이 복원이
    // 같은 협회를 채우면 사용자가 stale 시트에서 그걸 또 고를 수 있다. 같은
    // org 가 두 번 저장되면 PK 충돌로 insert 가 통째로 실패하는데, 그 앞의
    // delete-all 은 이미 커밋돼 협회가 전멸한다(codex 2차 #1).
    test('같은 협회를 두 번 추가하지 않는다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      expect(src, contains('!_orgs.any((o) => o.org == picked)'),
          reason: '_addOrg 는 이미 있는 협회를 다시 넣지 않아야 한다 —'
              ' 중복 행은 insert 실패로 이어지고, delete-all 은 이미 커밋된다');
    });

    // 복원이 늦는 사이 협회를 하나 추가하면 _addOrg 가 그걸 자동으로 주 협회로
    // 세운다. 그 자동값까지 존중하면 서버의 is_primary 가 조용히 바뀐다
    // (codex 2차 #2). 라디오로 직접 고른 것만 존중해야 한다.
    test('주 협회는 직접 고른 것만 존중한다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      expect(src, contains('if (!_primaryOrgTouched) {'),
          reason: '복원은 _addOrg 가 자동으로 세운 주 협회를 서버 값으로 덮어야 한다');
      expect(src, contains('_primaryOrgTouched = true;'),
          reason: '_setPrimaryOrg 가 직접 선택을 표시해야 복원이 그것만 존중한다');
    });

    // 직접 고른 협회를 다시 지우면 _primaryOrg 는 null 이 되는데 touched 는
    // 그대로 true 다. 그 상태로 복원이 도착하면 위 분기를 건너뛰어, 협회는
    // 있는데 아무도 primary 가 아닌 payload 가 저장된다(codex 3차 #2/#4).
    test('협회가 있으면 주 협회도 남긴다', () {
      final src =
          File('lib/screens/auth/onboarding_screen.dart').readAsStringSync();
      expect(src, contains('_primaryOrg ??= _orgs.firstOrNull?.org;'),
          reason: '복원 끝에 주 협회 불변식을 복구해야 한다 —'
              ' 협회 목록이 비어 있지 않으면 주 협회가 하나 있어야 한다');
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
