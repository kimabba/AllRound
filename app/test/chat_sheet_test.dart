import 'package:allround/models/chat_entry_context.dart';
import 'package:allround/screens/chat_screen.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/widgets/app_bottom_nav.dart';
import 'package:allround/widgets/chat_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('대회 상세는 명시적 연결이 필요한 엔티티 문맥을 만든다', () {
    final context = chatEntryContextForPath('/tournaments/tournament-17');

    expect(context.screenLabel, '현재 대회');
    expect(context.entityType, 'tournament');
    expect(context.entityId, 'tournament-17');
    expect(context.attachEntityByDefault, isFalse);
  });

  test('클럽 상세는 명시적 연결이 필요한 엔티티 문맥을 만든다', () {
    final context = chatEntryContextForPath('/clubs/club-9');

    expect(context.screenLabel, '현재 클럽');
    expect(context.entityType, 'club');
    expect(context.entityId, 'club-9');
    expect(context.attachEntityByDefault, isFalse);
  });

  test('일반 화면은 개인 엔티티를 자동으로 연결하지 않는다', () {
    final context = chatEntryContextForPath('/rules');

    expect(context.screenLabel, '룰북');
    expect(context.canAttachEntity, isFalse);
  });

  test('바텀시트에서 전체 화면으로 확장할 때 작성 중인 질문을 유지한다', () {
    final context = chatEntryContextForPath('/').copyWith(
      initialMessage: '작성 중인 질문',
    );

    expect(context.initialMessage, '작성 중인 질문');
  });

  testWidgets('전역 AI 진입창에서 절반 높이 채팅 시트를 연다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
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

    expect(find.byKey(AllRoundE2EKeys.globalChatDock), findsOneWidget);

    await tester.tap(find.byKey(AllRoundE2EKeys.globalChatDock));
    await tester.pumpAndSettle();

    expect(find.text('현재 대회 연결'), findsOneWidget);
    expect(find.text('참가 가능 여부'), findsOneWidget);
    expect(find.text('신청 준비 정리'), findsOneWidget);

    final sendButtonFinder = find.widgetWithIcon(
      IconButton,
      Icons.arrow_upward_rounded,
    );
    expect(
      tester.widget<IconButton>(sendButtonFinder).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '신청 준비를 알려줘');
    await tester.pump();

    expect(
      tester.widget<IconButton>(sendButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('전체 화면 확장 콜백에 작성 중인 초안을 전달한다', (tester) async {
    ChatEntryContext? expandedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatScreen(
              embedded: true,
              entryContext: chatEntryContextForPath('/'),
              onExpand: (context) => expandedContext = context,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '확장 전 초안');
    await tester.tap(find.byTooltip('전체 화면으로 열기'));
    await tester.pump();

    expect(expandedContext?.initialMessage, '확장 전 초안');
  });

  testWidgets('전역 시트에서 확장한 전체 채팅이 초안을 복원한다', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            bottomNavigationBar: Builder(
              builder: (context) => AppBottomNav(
                currentIndex: 0,
                onChanged: (_) {},
                onChatTap: () =>
                    openChatSheet(context, chatEntryContextForPath('/')),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat',
          builder: (_, state) => ChatScreen(
            entryContext: state.extra is ChatEntryContext
                ? state.extra! as ChatEntryContext
                : null,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.tap(find.byKey(AllRoundE2EKeys.globalChatDock));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '라우터 확장 초안');
    await tester.tap(find.byTooltip('전체 화면으로 열기'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/chat');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '라우터 확장 초안',
    );
  });
}
