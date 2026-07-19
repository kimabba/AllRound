import 'dart:async';

import 'package:allround/screens/chat_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _ChatStreamFactory = Stream<ChatStreamEvent> Function(String message);

class _FakeChatApi extends ApiService {
  _FakeChatApi(this._streamFactory)
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'qa-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final _ChatStreamFactory _streamFactory;

  @override
  Stream<ChatStreamEvent> chat({
    required String message,
    String? conversationId,
    bool enableSearch = true,
    String? activeSport,
    Map<String, String>? selectedEntity,
    Map<String, dynamic>? tournamentRefine,
  }) {
    return _streamFactory(message);
  }
}

void main() {
  Future<void> pumpChat(
    WidgetTester tester, {
    required _ChatStreamFactory streamFactory,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_FakeChatApi(streamFactory)),
          activeSportProvider.overrideWithValue('tennis'),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const ChatScreen(),
          ),
        ),
      ),
    );
  }

  Future<void> send(WidgetTester tester, String message) async {
    await tester.enterText(
      find.byKey(AllRoundE2EKeys.chatInput),
      message,
    );
    await tester.pump();
    expect(find.byTooltip('메시지 보내기'), findsOneWidget);
    await tester.tap(find.byTooltip('메시지 보내기'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  void useSmallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('slow chat exposes progress and an immediate stop action',
      (tester) async {
    final controller = StreamController<ChatStreamEvent>();
    addTearDown(() {
      if (!controller.isClosed) unawaited(controller.close());
    });
    await pumpChat(tester, streamFactory: (_) => controller.stream);

    await send(tester, '응답이 느린 상황 테스트');

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('응답 중지'), findsOneWidget);
    await tester.tap(find.byTooltip('응답 중지'));
    await tester.pump();
    expect(find.byTooltip('응답 중지'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat errors hide internal details and show a retryable message',
      (tester) async {
    await pumpChat(
      tester,
      streamFactory: (_) => Stream<ChatStreamEvent>.error(
        Exception('GEMINI_API_KEY API_KEY_INVALID secret detail'),
      ),
    );

    await send(tester, '오류 상황 테스트');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('AI 코치를 일시적으로 이용할 수 없어요'), findsOneWidget);
    expect(find.textContaining('GEMINI_API_KEY'), findsNothing);
    expect(find.textContaining('API_KEY_INVALID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long Korean chat remains usable in dark mode at 200% text',
      (tester) async {
    useSmallPhone(tester);
    const response = '서울과 경기 지역에서 참가할 수 있는 대회를 찾았습니다. '
        '신청 기간과 참가 자격, 경기 장소, 준비물을 차례대로 확인한 뒤 '
        '원하는 대회 카드를 선택해 상세 정보를 확인하세요.';
    await pumpChat(
      tester,
      streamFactory: (_) => Stream.fromIterable([
        ChatStreamEvent('delta', {'text': response}),
      ]),
      theme: AppTheme.dark(),
      textScale: 2,
    );

    await send(tester, '긴 한글 답변을 보여줘');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is MarkdownBody && widget.data.contains('서울과 경기 지역'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.byKey(AllRoundE2EKeys.chatInput), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
