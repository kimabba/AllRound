import 'package:flutter_test/flutter_test.dart';

import 'package:allround/screens/auth/onboarding_screen.dart';

// 실명 칸(users.name)은 협회 랭킹표의 선수명과 글자까지 같아야 본인 연결
// 후보가 붙는다. 길이 검사만 있던 동안 `이름1` 같은 값이 절반이었다.
void main() {
  test('한글 실명 2~6자만 통과한다', () {
    for (final ok in ['김민수', '남궁도원', '이도', ' 김민수 ', '남궁하늘가']) {
      expect(isValidRealName(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '',
      '김',
      '남궁하늘가람별',
      '테니스왕1',
      'John Kim',
      '김 민수',
      'ㅋㅋ홍길동',
      '김민수!',
    ]) {
      expect(isValidRealName(bad), isFalse, reason: bad);
    }
  });

  test('한글 닉네임은 이 검사로 못 거른다 — 관리자 승인 단계 몫이다', () {
    expect(isValidRealName('테니스왕'), isTrue);
  });

  test('가입 트리거가 만든 이메일 앞부분 이름은 복원 대상이 아니다', () {
    // users.name 기본값은 split_part(email,'@',1) 이다. 재진입 때 이걸 칸에
    // 되돌리면 사용자가 자기 실명으로 오인한 채 그대로 저장한다.
    for (final generated in ['tennis1', 'ssfak', 'demian.772']) {
      expect(isValidRealName(generated), isFalse, reason: generated);
    }
  });
}
