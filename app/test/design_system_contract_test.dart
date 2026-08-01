import 'dart:math' as math;

import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/color_schemes.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {

  // 로그인 히어로의 색 조합은 Flutter 의 textContrastGuideline 이 놓친다(pill 은
  // 실제로 렌더되는데도 다크 4.04:1 미달이 검출되지 않았다). 그래서 조합의 대비를
  // 토큰에서 직접 계산해 못 박는다.
  //
  // 한계 — 이 테스트는 색 '조합'을 검사할 뿐 위젯이 그 조합을 쓰는지는 보지 않는다.
  // 토큰 색이나 alpha 가 바뀌면 잡히지만, 위젯이 다른 색으로 갈아타면 못 잡는다.
  // 값은 login_screen.dart 의 _FeaturePill / 히어로 본문과 짝을 맞춰 유지할 것.
  test('로그인 히어로 색 조합이 WCAG AA(4.5:1) 를 만족한다', () {
    const bodyAlpha = 0.8; // 히어로 본문 텍스트
    const pillBackgroundAlpha = 0.08; // _FeaturePill 배경

    for (final entry in {
      '라이트': appLightScheme,
      '다크': appDarkScheme,
    }.entries) {
      final scheme = entry.value;
      final container = scheme.primaryContainer;

      final bodyColor = Color.alphaBlend(
        scheme.onPrimaryContainer.withValues(alpha: bodyAlpha),
        container,
      );
      expect(
        _contrastRatio(bodyColor, container),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key}: 히어로 본문 대비가 AA 기준에 미달합니다.',
      );

      final pillBackground = Color.alphaBlend(
        scheme.onPrimaryContainer.withValues(alpha: pillBackgroundAlpha),
        container,
      );
      expect(
        _contrastRatio(scheme.onPrimaryContainer, pillBackground),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key}: pill 텍스트 대비가 AA 기준에 미달합니다.',
      );
    }
  });

  test('Pureform fixed component sizes stay on the documented contract', () {
    expect(AppSizes.touchTarget, 48);
    expect(AppSizes.control, 48);
    expect(AppSizes.appBar, 56);
    expect(AppSizes.listRow, 56);
    expect(AppSizes.bottomNavigation, 64);
  });

  testWidgets('small screen and 130% text keep the bottom action region usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(
                currentIndex: 0,
                onChanged: (_) {},
                onChatTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    expect(find.text('일정'), findsOneWidget);
    expect(find.text('룰북'), findsOneWidget);
    expect(find.text('볼보이'), findsOneWidget);
  });

  testWidgets('200% text keeps the bottom nav within its fixed region',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onChanged: (_) {},
              onChatTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppBottomNav)),
      const Size(320, AppSizes.bottomNavigation + bottomNavDialProtrusion),
    );
  });
}

/// WCAG 2.1 상대 명도 대비. 1.0(동일) ~ 21.0(흑백) 범위.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
