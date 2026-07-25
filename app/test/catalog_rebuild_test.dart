import 'dart:io';

import 'package:allround/utils/grade_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// #318: 카탈로그는 plain singleton 이라 라벨을 읽는 화면에 리빌드 트리거가 없다.
/// `catalogAware` 가 라우트 화면을 `catalogRevision` 마다 새로 만들어
/// 이 문제를 덮는다. 여기서 검증하는 건 그 방식이 실제로 화면을 갱신하는가다.
///
/// 실측으로 탈락한 대안 2개(같은 실수 반복 방지):
///  - MaterialApp.router 를 ListenableBuilder 로 감싸기 → GoRouter 가 화면 위젯을
///    캐시해 하위 트리가 안 그려진다.
///  - GoRouter 의 refreshListenable 에 물리기 → 같은 이유로 안 그려진다.
void main() {
  tearDown(() {
    GradeCatalog.instance.reset();
    DivisionCatalog.instance.reset();
  });

  Widget appUnderTest(Widget Function() screen) {
    final router = GoRouter(
      routes: [
        // 프로덕션과 같은 헬퍼를 쓴다(복제하면 헬퍼가 바뀌어도 테스트가 안 깨진다).
        GoRoute(path: '/', builder: (_, __) => catalogAware(screen)),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('로드가 늦게 끝나도 이미 그려진 화면의 등급 라벨이 갱신된다', (tester) async {
    await tester.pumpWidget(
      appUnderTest(() => Scaffold(body: Text(gradeLabel('elite')))),
    );
    // 로드 전: 번들 폴백 라벨.
    expect(find.text('선출'), findsOneWidget);

    // 화면이 이미 그려진 뒤 DB 결과가 도착한다(로그아웃 시작 → 로그인 경로).
    GradeCatalog.instance.ingestRows([
      {'sport': 'futsal', 'code': 'elite', 'label_ko': '프로', 'is_active': true},
    ]);
    await tester.pump();

    expect(find.text('프로'), findsOneWidget);
    expect(find.text('선출'), findsNothing);
  });

  testWidgets('부서 라벨도 같은 경로로 갱신된다', (tester) async {
    await tester.pumpWidget(
      appUnderTest(() => Scaffold(body: Text(divisionLabel('gj_m_gold')))),
    );
    expect(find.text('골드부'), findsOneWidget);

    DivisionCatalog.instance.ingestRows([
      {
        'code': 'gj_m_gold',
        'org_code': 'gj',
        'label_ko': '골드부(개명)',
        'gender': 'male',
      },
    ]);
    await tester.pump();

    expect(find.text('골드부(개명)'), findsOneWidget);
  });

  // 위 테스트는 방식이 동작함을 보이지만 router.dart 에 실제로 연결됐는지는 못 본다.
  // 새 라우트를 catalogAware 없이 추가하면 그 화면만 조용히 stale 이 되므로 여기서 막는다.
  //
  // 개수를 세는 방식(`GoRoute(` 수 vs `catalogAware(` 수)은 쓰지 않는다 — 감싸지 않은
  // 라우트를 추가해도 다른 곳(주석 포함)에 `catalogAware(` 가 하나 더 있으면 통과한다.
  // 라우트마다 자기 블록을 따로 검사한다.
  test('router.dart 의 모든 라우트가 각자 catalogAware 를 거친다', () {
    final blocks = _routeBlocks(File('lib/router.dart').readAsStringSync());

    // 라우트가 통째로 사라져 검사가 공회전하는 상황을 막는다.
    expect(blocks.length, greaterThanOrEqualTo(20),
        reason: 'GoRoute 블록을 제대로 못 읽었다(파서 문제일 수 있음)');

    for (final block in blocks) {
      final head = block.split('\n').first.trim();
      expect(block.contains('catalogAware('), isTrue,
          reason: 'catalogAware 로 감싸지 않은 라우트: $head');
      // 감싸도 클로저 안이 const 면 인스턴스가 재사용돼 갱신이 스킵된다.
      // `const ` 문자열이 아니라 토큰 경계로 본다 — `const` 뒤에 줄바꿈을 넣으면
      // 문법상 유효하면서 문자열 검사만 피해간다(codex 재리뷰 실증).
      expect(RegExp(r'\bconst\b').hasMatch(block), isFalse,
          reason: 'const 화면은 인스턴스가 재사용돼 갱신되지 않는다: $head');
    }
  });

  testWidgets('reset 도 화면을 폴백으로 되돌린다 — 로그아웃 후 이전 계정 라벨이 남지 않는다',
      (tester) async {
    GradeCatalog.instance.ingestRows([
      {'sport': 'futsal', 'code': 'elite', 'label_ko': '프로', 'is_active': true},
    ]);
    await tester.pumpWidget(
      appUnderTest(() => Scaffold(body: Text(gradeLabel('elite')))),
    );
    expect(find.text('프로'), findsOneWidget);

    GradeCatalog.instance.reset();
    await tester.pump();

    expect(find.text('선출'), findsOneWidget);
  });
}

/// `GoRoute(` 하나하나의 인자 블록을 괄호 균형으로 잘라낸다.
///
/// 주석(줄·블록)은 먼저 제거한다 — 주석 안의 `GoRoute(`/`catalogAware(` 가 검사를
/// 흐리기 때문이다.
///
/// **목표는 "실수 차단"이지 "의도적 우회 차단"이 아니다.** 문자열 매칭 기반이라
/// 문자열 리터럴 안의 괄호·주석 흉내 같은 건 구분하지 못한다. 원리적으로 견고한
/// 소스 검사는 #322(정규식 렉서 → analyzer AST) 범위다. 이 리포는 자작 렉서를
/// 덧대다 사각지대를 반복 생산한 이력이 있어(JY-146 13~15차) 여기서 더 정교하게
/// 만들지 않는다.
List<String> _routeBlocks(String source) {
  final stripped = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .map((line) {
    final i = line.indexOf('//');
    return i == -1 ? line : line.substring(0, i);
  }).join('\n');

  const marker = 'GoRoute(';
  final blocks = <String>[];
  var from = 0;
  while (true) {
    final start = stripped.indexOf(marker, from);
    if (start == -1) break;
    var depth = 0;
    var end = start + marker.length - 1;
    for (var i = start + marker.length - 1; i < stripped.length; i++) {
      final c = stripped[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    blocks.add(stripped.substring(start, end + 1));
    from = start + marker.length;
  }
  return blocks;
}
