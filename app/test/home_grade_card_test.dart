import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/home_screen.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

OrgRankingRow _row({
  required String divisionCode,
  String orgCode = 'gj',
  int rank = 12,
  int totalPoints = 800,
}) =>
    OrgRankingRow(
      orgCode: orgCode,
      divisionCode: divisionCode,
      rank: rank,
      playerName: '홍길동',
      rankPoints: totalPoints,
      totalPoints: totalPoints,
    );

Future<void> _pumpHome(
  WidgetTester tester,
  MyGradeSummary? summary, {
  double textScale = 1,
  String activeSport = 'tennis',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, __) => null,
      overrides: [
        homeTournamentsProvider.overrideWith((ref) async => const <Tournament>[]),
        myTournamentRecordsProvider
            .overrideWith((ref) async => const <Tournament>[]),
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
        activeSportProvider.overrideWith((ref) => activeSport),
        myGradeSummaryProvider.overrideWith((ref) async => summary),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const HomeScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Club> _clubs(int futsalCount, {int tennisCount = 0}) => [
      for (var i = 0; i < futsalCount; i++)
        Club(id: 'futsal-club-$i', sport: 'futsal', name: '풋살 클럽 $i'),
      for (var i = 0; i < tennisCount; i++)
        Club(id: 'tennis-club-$i', sport: 'tennis', name: '테니스 클럽 $i'),
    ];

Future<void> _pumpHomeFutsal(
  WidgetTester tester, {
  required String grade,
  List<Club>? clubs,
  int? attendCount,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, __) => null,
      overrides: [
        homeTournamentsProvider.overrideWith((ref) async => const <Tournament>[]),
        myTournamentRecordsProvider
            .overrideWith((ref) async => const <Tournament>[]),
        unreadNotificationCountProvider.overrideWith((ref) async => 0),
        activeSportProvider.overrideWith((ref) => 'futsal'),
        userSportsProvider.overrideWith(
          (ref) async => [UserSport(sport: 'futsal', grade: grade)],
        ),
        myClubsProvider.overrideWith((ref) async => clubs ?? const <Club>[]),
        myFutsalAttendanceCountThisYearProvider
            .overrideWith((ref) async => attendCount ?? 0),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const HomeScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  group('topDivisionRanking', () {
    // 골드부와 일반부에 동시에 이름이 올라 있으면 카드에는 위 부서가 떠야 한다.
    // 코드 알파벳순으로 고르면 gj_m_general(일반부)이 먼저 걸린다.
    test('협회가 공표하는 순서에서 위쪽 부서를 고른다', () {
      final picked = topDivisionRanking([
        _row(divisionCode: 'gj_m_general'),
        _row(divisionCode: 'gj_m_gold'),
      ]);
      expect(picked?.divisionCode, 'gj_m_gold');
    });

    test('랭킹 미러가 없는 부서만 있으면 그것이라도 고른다', () {
      final picked = topDivisionRanking([_row(divisionCode: 'kato_masters')]);
      expect(picked?.divisionCode, 'kato_masters');
    });

    test('빈 목록이면 null 이라 카드가 뜨지 않는다', () {
      expect(topDivisionRanking(const []), isNull);
    });

    // kRankingDivisions 에 협회 자체가 없으면(미러 확장 과도기) 목록에 있는
    // 협회의 1순위 부서와 우연히 같은 tier(0)로 묶여 잘못 앞서 뽑히면 안 된다.
    test('협회 자체가 미러 목록에 없으면 목록에 있는 협회 뒤로 밀린다', () {
      final picked = topDivisionRanking([
        _row(orgCode: 'kata', divisionCode: 'kata_1'),
        _row(orgCode: 'gj', divisionCode: 'gj_m_general'),
      ]);
      expect(picked?.orgCode, 'gj');
    });
  });

  testWidgets('연결이 없으면 등급 카드를 그리지 않는다', (tester) async {
    await _pumpHome(tester, null);

    expect(find.textContaining('랭킹 '), findsNothing);
    expect(find.text('시즌 포인트'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 풋살은 랭킹 미러가 없다. 종목을 바꿨는데 테니스 랭킹 카드가 남아 있으면
  // 지금 보고 있는 종목과 카드가 어긋난다.
  testWidgets('풋살을 보고 있으면 테니스 랭킹이 있어도 카드를 숨긴다', (tester) async {
    await _pumpHome(
      tester,
      (ranking: _row(divisionCode: 'gj_m_general'), top10Points: 1200),
      activeSport: 'futsal',
    );

    expect(find.text('랭킹 12위'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOP 10 밖이면 남은 포인트를 보여준다', (tester) async {
    await _pumpHome(
      tester,
      (ranking: _row(divisionCode: 'gj_m_general'), top10Points: 1200),
    );

    expect(find.text('일반부'), findsOneWidget);
    expect(find.text('광주협회 기준'), findsOneWidget);
    expect(find.text('랭킹 12위'), findsOneWidget);
    expect(find.text('800P'), findsOneWidget);
    expect(find.text('TOP 10까지 400P'), findsOneWidget);
    expect(find.text('승급은 입상 실적으로 결정돼요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 협회가 순위를 매기는 기준과 표시 점수가 어긋날 수 있다. 그때 "-120P 남음"
  // 같은 값이 나오면 안 된다.
  testWidgets('내 점수가 커트라인보다 높아도 남은 포인트는 음수가 되지 않는다', (tester) async {
    await _pumpHome(
      tester,
      (
        ranking: _row(divisionCode: 'gj_m_general', totalPoints: 1500),
        top10Points: 1200,
      ),
    );

    expect(find.text('TOP 10까지 0P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOP 10 안이면 남은 포인트 대신 현재 상태를 말한다', (tester) async {
    await _pumpHome(
      tester,
      (
        ranking: _row(divisionCode: 'gj_m_gold', rank: 3, totalPoints: 2400),
        top10Points: 1200,
      ),
    );

    expect(find.text('TOP 10 안에 있어요'), findsOneWidget);
    expect(find.text('2,400P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 10명이 안 되는 부서는 커트라인 자체가 없다. 0% 막대를 그리면 꼴찌로 읽힌다.
  testWidgets('커트라인을 모르면 막대와 안내를 생략한다', (tester) async {
    await _pumpHome(
      tester,
      (ranking: _row(divisionCode: 'gj_m_general'), top10Points: null),
    );

    expect(find.textContaining('TOP 10'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('랭킹 12위'), findsOneWidget);
    // 승급 안내는 커트라인과 무관하므로 남는다.
    expect(find.text('승급은 입상 실적으로 결정돼요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면 200% 글자에서도 카드가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHome(
      tester,
      (ranking: _row(divisionCode: 'gj_m_general'), top10Points: 1200),
      textScale: 2,
    );

    expect(find.text('시즌 포인트'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('풋살 등급 카드가 통계와 함께 뜬다', (tester) async {
    await _pumpHomeFutsal(
      tester,
      grade: 'elite',
      clubs: _clubs(3),
      attendCount: 7,
    );

    expect(find.text('내 등급'), findsOneWidget);
    expect(find.text('가입한 클럽'), findsOneWidget);
    expect(find.text('이번 시즌 참가'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('7회'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 회귀 테스트: 테니스·풋살 클럽에 모두 가입한 사용자도 "가입한 클럽" 수는
  // 풋살만 세야 한다(PR #498 재리뷰에서 발견 — myClubsProvider가 종목 구분
  // 없이 전체 클럽을 돌려줘서 테니스 클럽이 섞여 세이던 버그).
  testWidgets('테니스 클럽에도 가입했어도 가입한 클럽 수는 풋살만 센다', (tester) async {
    await _pumpHomeFutsal(
      tester,
      grade: 'elite',
      clubs: _clubs(3, tennisCount: 5),
      attendCount: 7,
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('8'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면 200% 글자에서도 풋살 카드가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpHomeFutsal(
      tester,
      grade: 'elite',
      clubs: _clubs(12),
      attendCount: 48,
      textScale: 2,
    );

    expect(find.text('내가 설정한 등급 · '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
