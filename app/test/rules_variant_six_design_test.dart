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

class _VariantSixRulesApi extends ApiService {
  _VariantSixRulesApi()
      : super(
          SupabaseClient(
            'https://rules-variant-six.invalid',
            'rules-variant-six-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final rules = <RuleArticle>[
    _rule('game-time', '경기 진행', '풋살 경기 시간'),
    _rule('players', '경기 진행', '선수 수와 교체'),
    _rule('kick-off', '경기 진행', '킥오프와 재개'),
    _rule('time-out', '경기 진행', '타임아웃'),
    _rule('period-end', '경기 진행', '전후반 종료'),
    _rule('direct-free-kick', '파울', '직접 프리킥'),
    _rule('penalty-kick', '파울', '페널티킥'),
  ];

  static RuleArticle _rule(String id, String category, String title) {
    return RuleArticle(
      id: id,
      sport: 'futsal',
      category: category,
      title: title,
      body: '$title의 핵심 규칙과 경기 적용 방법입니다.',
      orderIdx: 0,
      published: true,
    );
  }

  @override
  Future<List<RuleArticle>> listRules(String sport) async => rules;

  @override
  Future<RulePopularityHighlight?> popularRuleHighlight24h(
    String sport,
  ) async {
    return RulePopularityHighlight(
      articleId: 'game-time',
      sport: sport,
      category: '경기 진행',
      title: '풋살 경기 시간',
      articleClickCount: 18,
      categoryClickCount: 31,
      windowStartedAt: DateTime(2026, 8, 19),
    );
  }
}

void main() {
  Widget app() {
    return ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(_VariantSixRulesApi()),
        activeSportProvider.overrideWithValue('futsal'),
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
        currentUserProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const RulesScreen(initialSport: 'futsal'),
      ),
    );
  }

  testWidgets('확정 시안 6의 카드뉴스와 첫 분류 펼침을 표시한다', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('오늘 가장 많이 받은 클릭'), findsOneWidget);
    expect(find.text('최근 24시간'), findsOneWidget);
    expect(find.text('풋살 경기 시간'), findsWidgets);
    expect(find.text('전체 룰북'), findsOneWidget);
    expect(find.text('2개 분류 · 7개 규칙'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('5개 규칙 모두 보기'), findsOneWidget);
  });

  testWidgets('아코디언 분류를 바꾸고 상세에서 같은 목록으로 돌아간다', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 왼쪽 카테고리 레일에도 같은 이름의 항목이 생겨 '파울'이 두 번
    // 매치된다 — 아코디언 헤더(뒤에 있는 쪽)를 골라 탭한다.
    await tester.ensureVisible(find.text('파울').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('파울').last);
    await tester.pumpAndSettle();

    expect(find.text('직접 프리킥'), findsOneWidget);
    expect(find.text('2개 규칙 모두 보기'), findsOneWidget);

    await tester.ensureVisible(find.text('2개 규칙 모두 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2개 규칙 모두 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 프리킥').last);
    await tester.pumpAndSettle();

    expect(find.text('파울 목록'), findsOneWidget);
    expect(find.textContaining('직접 프리킥의 핵심 규칙'), findsOneWidget);

    await tester.tap(find.text('파울 목록'));
    await tester.pumpAndSettle();

    expect(find.text('직접 프리킥'), findsWidgets);
    expect(find.textContaining('직접 프리킥의 핵심 규칙'), findsNothing);
  });

  testWidgets('스크롤해도 인기 카드와 검색 영역은 상단에 고정된다', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final card = find.text('오늘 가장 많이 받은 클릭');
    final before = tester.getTopLeft(card).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(card).dy, closeTo(before, 0.5));
    expect(find.text('룰 검색하기...'), findsOneWidget);
  });

  testWidgets('작은 화면 200% 글자에서도 카테고리 레일이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_VariantSixRulesApi()),
          activeSportProvider.overrideWithValue('futsal'),
          unreadNotificationCountProvider.overrideWith((ref) async => 0),
          currentUserProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const RulesScreen(initialSport: 'futsal'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('경기 진행'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // 회귀 테스트: 주 종목이 설정된 실사용자가 '룰북' 탭을 그냥 열었을 때
  // (initialSport 없이, activeSportProvider가 실제 값을 주는 상태) 레일이
  // 진짜로 렌더링되는지 확인한다. initialSport를 명시로 넘기는 다른 테스트들은
  // 이 경로를 타지 않아 종목 폴백 버그를 잡지 못했다(PR #498 리뷰에서 발견).
  testWidgets('주 종목이 있는 사용자가 룰북을 열어도 레일이 뜬다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_VariantSixRulesApi()),
          activeSportProvider.overrideWithValue('futsal'),
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

    // 레일의 종목 전환 항목 — 단일종목 읽기 화면이었다면 안 뜬다.
    expect(find.text('테니스'), findsOneWidget);
    expect(find.text('풋살'), findsOneWidget);

    await tester.tap(find.text('테니스'));
    await tester.pumpAndSettle();

    expect(find.text('경기 진행'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // 회귀 테스트: 레일에서 종목을 바꾸면 화면 로컬 상태만 바뀌는 게 아니라
  // 앱 전체 기준점(activeSportProvider)도 같이 바뀌어야 한다 — 안 그러면
  // 룰북 안에서는 풋살을 보고 있는데 상단 탭바(TournamentSectionBar)는
  // 여전히 이전 종목 기준으로 "랭킹" 탭을 보여주는 식으로 화면 안에서까지
  // 어긋난다(PR #498 재리뷰에서 발견). activeSportProvider를 직접
  // 오버라이드하지 않고 userSportsProvider로만 주 종목을 줘서, 레일 탭이
  // 진짜로 sportOverrideProvider를 거쳐 전파되는지까지 확인한다.
  testWidgets('레일에서 종목을 바꾸면 앱 전체 종목 기준점도 따라간다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(_VariantSixRulesApi()),
          userSportsProvider.overrideWith(
            (ref) async => [
              UserSport(sport: 'tennis', grade: 'div3', isPrimary: true),
            ],
          ),
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

    // 주 종목이 테니스라 시작은 테니스 — 랭킹 탭이 보인다.
    expect(find.text('랭킹'), findsOneWidget);

    await tester.tap(find.text('풋살'));
    await tester.pumpAndSettle();

    // 레일 탭이 activeSportProvider까지 바꿔서, 풋살엔 없는 랭킹 탭이
    // TournamentSectionBar에서도 함께 사라져야 한다.
    expect(find.text('랭킹'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
