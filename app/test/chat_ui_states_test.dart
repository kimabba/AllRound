import 'dart:async';

import 'package:allround/screens/chat_screen.dart';
import 'package:allround/widgets/chat_ai_disclosure.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/testing/e2e_keys.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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

  // ── 생성형 AI 고지 (인공지능기본법 §31·§43) ────────────────────────────
  //
  // check_static_rules 의 존재 검사는 문자열만 본다 — Offstage·Visibility(false)·
  // Opacity(0) 로 감싸거나 화면 밖에 두면 그대로 통과한다. 실제로 보이는지는
  // 여기서만 확인된다.

  testWidgets('AI 고지가 챗봇 화면에 실제로 보인다', (tester) async {
    await pumpChat(tester, streamFactory: (_) => const Stream.empty());

    // skipOffstage 기본값(true) 이라 Offstage 로 숨기면 findsNothing 이 된다.
    final disclosure = find.byType(ChatAiDisclosure);
    expect(disclosure, findsOneWidget);

    // 존재하지만 크기가 0이면 보이는 게 아니다.
    final size = tester.getSize(disclosure);
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));

    // 화면 안에 있어야 한다.
    final rect = tester.getRect(disclosure);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.top, lessThan(screen.height));
    expect(rect.bottom, greaterThan(0));

    // 문구 자체 — 'AI가 만들었다'와 '원문 확인' 두 축이 다 있어야 한다.
    expect(find.text(ChatAiDisclosure.text), findsOneWidget);
    expect(ChatAiDisclosure.text, contains('AI'));
    expect(ChatAiDisclosure.text, contains('확인'));

    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 고지는 스크린리더에 한 번만 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChat(tester, streamFactory: (_) => const Stream.empty());

    expect(
      find.bySemanticsLabel(ChatAiDisclosure.text),
      findsOneWidget,
      reason: 'Semantics + ExcludeSemantics 조합이 깨지면 0개(누락)나 2개(중복)가 된다',
    );

    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면 + 큰 글자에서도 고지 때문에 넘치지 않는다', (tester) async {
    useSmallPhone(tester);
    await pumpChat(
      tester,
      streamFactory: (_) => const Stream.empty(),
      textScale: 1.3,
    );

    expect(find.byType(ChatAiDisclosure), findsOneWidget);
    // 하단 비-flex 영역이 커지면 메시지 영역이 밀려 RenderFlex overflow 가 난다.
    expect(tester.takeException(), isNull);
  });
}
