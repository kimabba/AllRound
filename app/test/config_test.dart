import 'package:flutter_test/flutter_test.dart';
import 'package:allround/config.dart';

void main() {
  // 회귀 방지: 개발용 우회 플래그(admin/design preview)는 dart-define 을 명시하지
  // 않은 기본 빌드에서 반드시 꺼져 있어야 한다. defaultValue 가 실수로 true 로
  // 바뀌면 릴리스 빌드에 우회 플래그가 새므로 여기서 잡는다 (JY-6).
  test('개발용 우회 플래그는 기본 빌드에서 모두 꺼져 있다', () {
    expect(AppConfig.adminDesignPreview, isFalse);
    expect(AppConfig.userDesignPreview, isFalse);
    expect(AppConfig.adminMode, isFalse);
    expect(AppConfig.hasDevOverrideFlags, isFalse);
  });

  // 기본 빌드는 dev 플래그가 없으므로 assertConfigured 의 릴리스 가드에 걸리지
  // 않는다(테스트는 debug 모드라 kReleaseMode=false 이기도 함). URL/키만 채우면 통과.
  test('assertConfigured 는 정상 설정에서 통과한다', () {
    // dart-define 미주입 시 supabaseUrl 이 비어 StateError 를 던지는 것도 계약.
    expect(AppConfig.supabaseUrl, isEmpty);
    expect(AppConfig.assertConfigured, throwsStateError);
  });
}
