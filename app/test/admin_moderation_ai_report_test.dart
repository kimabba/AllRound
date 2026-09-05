import 'dart:convert';

import 'package:allround/models/moderation.dart';
import 'package:allround/screens/admin/moderation_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeModerationApi extends ApiService {
  _FakeModerationApi(super.client, this._reports);

  final List<UgcReport> _reports;

  @override
  Future<List<UgcReport>> adminUgcReports({String? status}) async => _reports;
}

UgcReport _aiReport() {
  return UgcReport.fromJson({
    'id': 'report-ai-1',
    'target_type': 'ai_message',
    'target_id': 'message-1',
    'reason': 'misinformation',
    'status': 'pending',
    'details': 'AI가 규칙을 틀리게 알려줬어요',
    'evidence_paths': <Object>[],
    'content_snapshot': {'content': '테니스는 5세트가 기본입니다.'},
    'created_at': '2026-09-01T00:00:00Z',
    'reporter': {'nickname': '신고자'},
    'reported_user': null,
    'reported_user_id': null,
  });
}

void main() {
  Future<void> pumpModeration(WidgetTester tester) async {
    final client = SupabaseClient(
      'http://127.0.0.1:54321',
      'qa-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final session = Session(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      tokenType: 'bearer',
      expiresIn: 3600,
      user: const User(
        id: 'admin-user',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-08-21T00:00:00Z',
      ),
    );
    await client.auth.setInitialSession(jsonEncode(session.toJson()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(
            _FakeModerationApi(client, [_aiReport()]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ModerationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AI 답변 신고에는 제재·삭제 대신 조치 기록 흐름을 안내한다', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpModeration(tester);

    // 목록 → 상세
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // 상세의 처리 버튼이 '삭제 · 제재 처리'가 아니라 '조치 기록'이어야 한다.
    expect(find.text('삭제 · 제재 처리'), findsNothing);
    final actionButton = find.text('조치 기록');
    expect(actionButton, findsOneWidget);

    await tester.tap(actionButton);
    await tester.pumpAndSettle();

    // 처리 다이얼로그: 제재·삭제 컨트롤은 숨고 안내가 보인다.
    expect(
      find.text('AI 답변 신고는 삭제·사용자 제재 대상이 없습니다.'),
      findsOneWidget,
    );
    expect(find.text('사용자 제재'), findsNothing);
    expect(find.text('신고된 콘텐츠 삭제'), findsNothing);
    expect(find.text('처리 사유 및 근거 *'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
