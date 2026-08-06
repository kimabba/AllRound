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

  test('저장돼 있던 이름 그대로면 규칙 위반이어도 통과시킨다', () {
    // 재진입한 기존 사용자가 이름을 바꾸기 전에는 못 빠져나가는 걸 막는다.
    expect(realNameAccepted('John Kim', 'John Kim'), isTrue);
    expect(realNameAccepted(' John Kim ', 'John Kim'), isTrue);
    // 손대는 순간 새 규칙을 적용한다.
    expect(realNameAccepted('John Kim2', 'John Kim'), isFalse);
    // 신규 가입자(복원값 없음)에게는 예외가 없다.
    expect(realNameAccepted('John Kim', null), isFalse);
    expect(realNameAccepted('John Kim', ''), isFalse);
  });
}
