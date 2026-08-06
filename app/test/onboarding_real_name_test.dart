import 'package:flutter_test/flutter_test.dart';

import 'package:allround/screens/auth/onboarding_screen.dart';

// 실명 칸(users.name)은 협회 랭킹표의 선수명과 글자까지 같아야 본인 연결
// 후보가 붙는다. 길이 검사만 있던 동안 `이름1` 같은 값이 절반이었다.
void main() {
  test('한글 실명 2~5자만 통과한다', () {
    for (final ok in ['김민수', '남궁도원', '이도', ' 김민수 ']) {
      expect(isValidRealName(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '',
      '김',
      '남궁도원가나',
      '테니스왕1',
      'John Kim',
      '김 민수',
      'ㅋㅋ홍길동',
      '김민수!',
    ]) {
      expect(isValidRealName(bad), isFalse, reason: bad);
    }
  });
}
