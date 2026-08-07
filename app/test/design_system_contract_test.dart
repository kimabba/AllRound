import 'dart:math' as math;

import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/color_schemes.dart';
import 'package:allround/theme/tokens.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 색 대비는 위젯 테스트(textContrastGuideline)가 아니라 여기서 못 박는다.
  // 그 가이드라인은 렌더된 픽셀을 샘플링하기 때문에 이 화면에서 양쪽으로 틀렸다:
  //   - 놓침: pill 이 렌더되는데도 다크 4.04:1 미달을 잡지 못했다
  //   - 거짓 양성: 11sp '로그인' 라벨이 Linux CI 에서 1.36:1 로 보고됐다. 실제 토큰
  //     기준으로는 라이트 4.76 / 다크 9.22 로 통과이며, 안티앨리어싱 가장자리 픽셀을
  //     본문 색으로 오인한 값이다(로컬 macOS 에서는 통과 — 환경 의존).
  // 토큰에서 직접 계산하면 렌더링 환경과 무관하게 같은 결론이 나온다.
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

      // 헤더의 보조 라벨('로그인'). 11sp 라 완화 기준이 적용되지 않는다.
      expect(
        _contrastRatio(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key}: 헤더 보조 라벨 대비가 AA 기준에 미달합니다.',
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
    expect(find.text('대회'), findsOneWidget);
    expect(find.text('클럽'), findsOneWidget);
    expect(find.text('룰북'), findsNothing);
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
      const Size(320, AppSizes.bottomNavigation),
    );
  });
}

/// WCAG 2.1 상대 명도 대비. 1.0(동일) ~ 21.0(흑백) 범위.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
