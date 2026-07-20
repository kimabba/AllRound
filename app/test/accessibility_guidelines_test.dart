import 'package:allround/screens/chat_screen.dart';
import 'package:allround/state/chat_state.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:allround/widgets/chat_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('하단 채팅과 내비게이션이 접근성 기준을 충족한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: AppBottomNav(
                currentIndex: 0,
                onChanged: (_) {},
                onChatTap: () {},
                chatHint: '대회 화면에서 채팅 열기',
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byKey(AllRoundE2EKeys.globalChatDock)),
        matchesSemantics(
          label: 'AI에게 물어보기',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(AllRoundE2EKeys.navToday)),
        matchesSemantics(
          label: '오늘 탭',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      await _expectCoreAccessibilityGuidelines(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('채팅 시트가 접근성 기준을 충족한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: Builder(
                builder: (context) => AppBottomNav(
                  currentIndex: 0,
                  onChanged: (_) {},
                  onChatTap: () => openChatSheet(
                    context,
                    chatEntryContextForPath('/tournaments/tournament-17'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(AllRoundE2EKeys.globalChatDock));
      await tester.pumpAndSettle();

      expect(find.text('현재 대회 연결'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(AllRoundE2EKeys.chatContextToggle)),
        matchesSemantics(
          label: '현재 대회 연결',
          value: '연결 안 됨',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byKey(AllRoundE2EKeys.chatContextToggle));
      await tester.pumpAndSettle();
      expect(find.byKey(AllRoundE2EKeys.chatContextAttached), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(AllRoundE2EKeys.chatContextToggle)),
        matchesSemantics(
          label: '현재 대회 연결',
          value: '연결됨',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      await _expectCoreAccessibilityGuidelines(tester);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('어두운 전체 채팅의 AI 답변과 출처 링크가 접근성 기준을 충족한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final chat = ChatNotifier();
    final assistant = ChatMessage(
      role: 'assistant',
      content: '참가 조건을 확인했습니다.',
    );
    assistant.citations = [
      {
        'type': 'web',
        'title': '공식 대회 요강',
        'url': 'https://example.invalid/tournament-rules',
      },
    ];
    chat.messages.add(assistant);

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatProvider.overrideWith((ref) => chat)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const ChatScreen(),
          ),
        ),
      );

      expect(find.text('공식 대회 요강'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'AI 답변.*참가 조건을 확인했습니다\.')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'출처 링크.*공식 대회 요강')),
        findsOneWidget,
      );
      await _expectCoreAccessibilityGuidelines(tester);
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _expectCoreAccessibilityGuidelines(WidgetTester tester) async {
  await expectLater(
    tester,
    meetsGuideline(labeledTapTargetGuideline),
    reason: '모든 터치 가능한 요소에는 낭독 가능한 이름이 있어야 합니다.',
  );
  await expectLater(
    tester,
    meetsGuideline(iOSTapTargetGuideline),
    reason: 'iOS의 최소 44x44 터치 영역을 지켜야 합니다.',
  );
  await expectLater(
    tester,
    meetsGuideline(androidTapTargetGuideline),
    reason: 'Android의 최소 48x48 터치 영역을 지켜야 합니다.',
  );
  await expectLater(
    tester,
    meetsGuideline(textContrastGuideline),
    reason: '핵심 텍스트는 WCAG 대비 기준을 충족해야 합니다.',
  );
}
