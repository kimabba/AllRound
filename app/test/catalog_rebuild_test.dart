import 'dart:io';

import 'package:allround/utils/grade_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// #318: 카탈로그는 plain singleton 이라 라벨을 읽는 화면에 리빌드 트리거가 없다.
/// router.dart 의 `_catalogAware` 가 라우트 화면을 `catalogRevision` 마다 새로 만들어
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
        GoRoute(
          path: '/',
          // router.dart 가 쓰는 것과 같은 래핑. 화면을 builder 안에서 새로 만드는 게
          // 핵심이다 — 같은 인스턴스를 돌려주면 Flutter 가 하위 트리를 건너뛴다.
          builder: (_, __) => ListenableBuilder(
            listenable: catalogRevision,
            builder: (_, __) => screen(),
          ),
        ),
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
  // 새 라우트를 _catalogAware 없이 추가하면 그 화면만 조용히 stale 이 되므로 여기서 막는다.
  test('router.dart 의 모든 라우트 화면이 _catalogAware 를 거친다', () {
    final source = File('lib/router.dart').readAsStringSync();
    final routeBuilders = RegExp(r'GoRoute\(').allMatches(source).length;
    final wrapped = RegExp(r'_catalogAware\(').allMatches(source).length;
    // 정의 1회 + 각 라우트 1회.
    expect(wrapped, greaterThanOrEqualTo(routeBuilders + 1),
        reason: '_catalogAware 로 감싸지 않은 라우트가 있다');
    expect(source.contains('builder: (_, __) => const '), isFalse,
        reason: 'const 화면은 인스턴스가 재사용돼 카탈로그 갱신이 반영되지 않는다');
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
