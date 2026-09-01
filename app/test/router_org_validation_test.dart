import 'package:allround/router.dart';
import 'package:flutter_test/flutter_test.dart';

// `/rankings/me?org=` 딥링크 오타·공백·폐기 코드가 "연결 안 됨"으로 오표시되지
// 않고 기존 기본 동작(정렬 1순위 협회)으로 강등되는지 검증한다. 실제 라우터
// 빌드는 인증·관리자 판정 등 provider 체인이 무거워, 검증 로직만 뽑아낸
// validatedRankingOrgCode 를 직접 테스트한다.
void main() {
  test('유효한 org 코드는 그대로 통과한다', () {
    expect(validatedRankingOrgCode('gj'), 'gj');
    expect(validatedRankingOrgCode('jn'), 'jn');
  });

  test('kRankingDivisions 에 없는 코드는 null 로 강등된다', () {
    expect(validatedRankingOrgCode('xx'), null);
  });

  test('앞뒤 공백이 섞인 코드는 trim 후 검증된다', () {
    expect(validatedRankingOrgCode('jn '), 'jn');
    expect(validatedRankingOrgCode(' xx '), null);
  });

  test('쿼리 파라미터가 없으면 null 이다', () {
    expect(validatedRankingOrgCode(null), null);
  });
}
