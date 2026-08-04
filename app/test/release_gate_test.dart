import 'dart:io';

import 'package:allround/config.dart';
import 'package:allround/services/release_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 게이트는 이 상수로 자기 빌드를 판정한다. pubspec 과 어긋나면 엉뚱한 버전을 막거나
  // (상수가 낮음) 막아야 할 버전을 통과시킨다(상수가 높음).
  //
  // 왜 harness(python 정규식)가 아니라 Dart 테스트인가: 정규식은 주석·문자열 안의 가짜
  // 선언을 실제 선언과 구분하지 못한다(codex 가 PR #386 에서 지적). 이 테스트는 컴파일된
  // 진짜 상수 값을 보므로 문법 사각지대가 원천적으로 없다 — check_org_parity.py 가 #322
  // 에서 도달한 결론과 같다: "소스 대상 검사는 실제 파서가 근본이다."
  test('AppConfig.appBuildNumber 가 pubspec 의 빌드번호와 같다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      match,
      isNotNull,
      reason: 'pubspec.yaml 의 `version: x.y.z+N` 을 읽지 못했다 — 형식이 바뀌었는지 확인할 것',
    );
    expect(
      AppConfig.appBuildNumber,
      int.parse(match!.group(1)!),
      reason: 'pubspec 이 정본이다 — config.dart 의 appBuildNumber 를 맞출 것',
    );
  });

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
