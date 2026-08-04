import 'package:allround/services/release_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isUpdateRequired', () {
    test('최소 빌드 미만이면 막는다', () {
      expect(
        isUpdateRequired(
          currentBuild: 5,
          gate: const ReleaseGate(minBuild: 6),
        ),
        isTrue,
      );
    });

    test('최소 빌드와 같으면 통과한다 (min_build 는 "이 값 이상 허용")', () {
      expect(
        isUpdateRequired(
          currentBuild: 6,
          gate: const ReleaseGate(minBuild: 6),
        ),
        isFalse,
      );
    });

    test('최소 빌드를 넘으면 통과한다', () {
      expect(
        isUpdateRequired(
          currentBuild: 7,
          gate: const ReleaseGate(minBuild: 6),
        ),
        isFalse,
      );
    });

    // 이 앱의 게이트에서 가장 중요한 성질. 서버 조회가 실패하면 gate 가 null 로 오고,
    // 그때 막아버리면 서버 장애가 곧 앱 전체 마비가 된다.
    test('게이트가 없으면(조회 실패) 통과시킨다 — fail-open', () {
      expect(isUpdateRequired(currentBuild: 1, gate: null), isFalse);
    });
  });
}
