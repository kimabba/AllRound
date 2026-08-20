import 'package:allround/models/rule_popularity.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/rules_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _PartialRulesApi extends ApiService {
  _PartialRulesApi()
      : super(
          SupabaseClient(
            'https://rules-test.invalid',
            'rules-test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<List<RuleArticle>> listRules(String sport) async {
    if (sport == 'tennis') throw StateError('tennis unavailable');
    return [
      RuleArticle(
        id: 'futsal-kick-in',
        sport: 'futsal',
        category: '경기 진행',
        title: '킥인은 어떻게 하나요?',
        body: '공이 나간 지점에서 킥인으로 경기를 재개합니다.',
        orderIdx: 0,
        published: true,
      ),
    ];
  }

  @override
  Future<RulePopularityHighlight?> popularRuleHighlight24h(
          String sport) async =>
      null;
}

void main() {
  testWidgets('테니스 조회가 실패해도 풋살 규칙은 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_PartialRulesApi()),
          activeSportProvider.overrideWithValue(null),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const RulesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테니스 룰북을 불러올 수 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('풋살'));
    await tester.pumpAndSettle();

    expect(find.text('킥인은 어떻게 하나요?'), findsOneWidget);
    expect(find.text('등록된 룰북이 없습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
