import 'package:allround/config.dart';
import 'package:allround/main.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    '실제 기기 프리뷰는 로고를 닫고 클럽 샘플 화면으로 진입한다',
    (tester) async {
      await initializeAllRoundPreviewServices();
      await tester.pumpWidget(
        ProviderScope(retry: (_, __) => null, child: const MatchUpApp()),
      );

      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final visibleLabels = tester
          .widgetList(find.byType(Text))
          .whereType<Text>()
          .map((widget) => widget.data)
          .whereType<String>()
          .toList();
      expect(
        find.text('나의 클럽'),
        findsOneWidget,
        reason: '현재 화면 텍스트: $visibleLabels',
      );
      expect(find.text('송도 유나이티드'), findsWidgets);
      final splash = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('startup-splash-opacity')),
      );
      expect(splash.opacity, 0);

      await tester.tap(find.byKey(AllRoundE2EKeys.globalChatDock));
      await tester.pumpAndSettle();
      expect(find.byKey(AllRoundE2EKeys.chatInput), findsOneWidget);

      await tester.enterText(
        find.byKey(AllRoundE2EKeys.chatInput),
        '가까운 대회 알려줘',
      );
      await tester.pump();
      expect(find.byTooltip('메시지 보내기'), findsOneWidget);
      await tester.tap(find.byTooltip('메시지 보내기'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byWidgetPredicate(
          (widget) => widget is MarkdownBody &&
              widget.data.contains('서울 챌린지컵'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('연결 실패'), findsNothing);
    },
    skip: !AppConfig.userDesignPreview,
  );
}
