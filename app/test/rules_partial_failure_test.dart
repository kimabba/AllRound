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
          // activeSportProvider를 직접 오버라이드하면 레일 탭이 실제로 거치는
          // sportOverrideProvider 변경에 반응하지 않는다(고정값이라 그
          // 아래에서 뭘 바꿔도 안 변함) — 주 종목이 없는 사용자를 만들 때도
          // 진짜 provider 체인(userSportsProvider가 비어서
          // activeSportProvider가 null이 되는 경로)을 그대로 써야 레일 탭이
          // 실제 동작대로 검증된다.
          userSportsProvider.overrideWith((ref) async => []),
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

    // 주 종목이 없는 사용자는 풋살을 기본으로 본다(다른 화면과 동일 기준) —
    // 그래서 실패한 테니스가 아니라 정상인 풋살이 처음부터 바로 보인다.
    // IndexedStack이 선택 안 된 쪽(테니스)은 화면에 그리지 않으므로 그
    // 상태를 확인하려면 skipOffstage: false 가 필요하다 — 기본 finder는
    // 화면에 그려지지 않는 위젯을 건너뛴다.
    expect(find.text('킥인은 어떻게 하나요?'), findsOneWidget);
    expect(
      find.text('테니스 룰북을 불러올 수 없어요', skipOffstage: false),
      findsOneWidget,
      reason: '테니스는 화면에 그려지지만(IndexedStack) 지금 보이는 쪽은 아니다',
    );

    await tester.tap(find.text('테니스'));
    await tester.pumpAndSettle();

    // 테니스로 전환하면 이제 그 실패 화면이 실제로 보인다 — "다시 시도"로
    // 복구할 수 있고, 풋살 규칙과 안 섞인다.
    expect(find.text('테니스 룰북을 불러올 수 없어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('등록된 룰북이 없습니다'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
