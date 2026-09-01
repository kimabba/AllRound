import 'dart:async';

import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/router.dart';
import 'package:allround/screens/rankings/my_record_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:allround/widgets/profile/my_record_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kOrgCode = 'gj';
const _kOrgPlayerId = 'player-1';

PlayerResult _result() => PlayerResult(
      orgCode: _kOrgCode,
      orgPlayerId: _kOrgPlayerId,
      tournamentName: '광주시장배',
      playedOn: DateTime(2026, 5, 1),
      resultRaw: '1',
      resultRound: 1,
      points: 1000,
    );

OrgRankingRow _ranking() => const OrgRankingRow(
      orgCode: _kOrgCode,
      divisionCode: 'gj_m_gold',
      rank: 3,
      playerName: '김평화',
      rankPoints: 1500,
      totalPoints: 1500,
      orgPlayerId: _kOrgPlayerId,
    );

OrgRankingSnapshot _snapshot() => OrgRankingSnapshot(
      orgCode: _kOrgCode,
      divisionCode: 'gj_m_gold',
      orgPlayerId: _kOrgPlayerId,
      capturedOn: DateTime(2026, 4, 1),
      rank: 4,
      totalPoints: 1400,
    );

/// [myRecordForOrgProvider] 가 링크를 한 번만 조회해 그 org_code/org_player_id
/// 로 하위 조회를 직접 호출하는지(Fix 2), 그리고 순위·순위추이(보조) 조회
/// 실패가 전적(핵심) 표시를 막지 않는지(Fix 1) 검증한다.
///
/// myPlayerResults/myCurrentRankings 를 호출하면 즉시 실패시켜, provider 가
/// 링크를 중복 조회하지 않는다는 걸 통과 자체로 증명한다.
class _FakeOrgRecordApi extends ApiService {
  _FakeOrgRecordApi({
    this.link,
    this.results = const [],
    this.rankings = const [],
    this.snapshots = const [],
    this.rankingsThrows = false,
    this.rankingHistoryThrows = false,
    this.rankingsPending,
  }) : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'qa-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final Map<String, dynamic>? link;
  final List<PlayerResult> results;
  final List<OrgRankingRow> rankings;
  final List<OrgRankingSnapshot> snapshots;
  final bool rankingsThrows;
  final bool rankingHistoryThrows;
  // 설정되면 playerRankings 가 이 Completer 가 완료될 때까지 절대 끝나지
  // 않는다 — aux(보조)가 pending 상태여도 core(전적)가 먼저 렌더되는지 검증용.
  final Completer<List<OrgRankingRow>>? rankingsPending;

  int confirmedLinkCalls = 0;
  int playerResultsCalls = 0;
  int playerRankingsCalls = 0;
  int playerRankingHistoryCalls = 0;

  @override
  Future<Map<String, dynamic>?> myConfirmedLink({String? orgCode}) async {
    confirmedLinkCalls++;
    return link;
  }

  @override
  Future<List<PlayerResult>> playerResults({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    playerResultsCalls++;
    return results;
  }

  @override
  Future<List<OrgRankingRow>> playerRankings({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    playerRankingsCalls++;
    if (rankingsPending != null) return rankingsPending!.future;
    if (rankingsThrows) throw Exception('rankings boom');
    return rankings;
  }

  @override
  Future<List<OrgRankingSnapshot>> playerRankingHistory({
    required String orgCode,
    required String divisionCode,
    required String orgPlayerId,
  }) async {
    playerRankingHistoryCalls++;
    if (rankingHistoryThrows) throw Exception('history boom');
    return snapshots;
  }

  // myRecordForOrgProvider(org 지정 진입)는 이 둘을 호출하면 안 된다 — 링크를
  // 중복 조회하게 된다(Fix 2). orgCode==null(기존 기본 진입 체인)은 그대로 통과.
  @override
  Future<List<PlayerResult>> myPlayerResults({String? orgCode}) async {
    if (orgCode != null) {
      throw StateError(
        'myRecordForOrgProvider 가 링크를 중복 조회했다(myPlayerResults 호출됨)',
      );
    }
    return results;
  }

  @override
  Future<List<OrgRankingRow>> myCurrentRankings({String? orgCode}) async {
    if (orgCode != null) {
      throw StateError(
        'myRecordForOrgProvider 가 링크를 중복 조회했다(myCurrentRankings 호출됨)',
      );
    }
    return rankings;
  }
}

Future<_FakeOrgRecordApi> _pumpOrgScreen(
  WidgetTester tester, {
  Map<String, dynamic>? link,
  List<PlayerResult> results = const [],
  List<OrgRankingRow> rankings = const [],
  List<OrgRankingSnapshot> snapshots = const [],
  bool rankingsThrows = false,
  bool rankingHistoryThrows = false,
}) async {
  final api = _FakeOrgRecordApi(
    link: link,
    results: results,
    rankings: rankings,
    snapshots: snapshots,
    rankingsThrows: rankingsThrows,
    rankingHistoryThrows: rankingHistoryThrows,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const MyRecordScreen(orgCode: _kOrgCode),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('myRecordForOrgProvider — 보조 조회 실패 격리(Fix 1)', () {
    testWidgets('순위추이 조회가 실패해도 전적은 표시된다', (tester) async {
      final api = await _pumpOrgScreen(
        tester,
        link: const {'org_code': _kOrgCode, 'org_player_id': _kOrgPlayerId},
        results: [_result()],
        rankings: [_ranking()],
        rankingHistoryThrows: true,
      );

      expect(find.text('광주시장배'), findsWidgets);
      expect(find.text('기록을 불러오지 못했습니다.'), findsNothing);
      expect(api.playerRankingHistoryCalls, 1);
    });

    testWidgets('순위 조회가 실패해도 전적은 표시된다', (tester) async {
      final api = await _pumpOrgScreen(
        tester,
        link: const {'org_code': _kOrgCode, 'org_player_id': _kOrgPlayerId},
        results: [_result()],
        rankingsThrows: true,
      );

      expect(find.text('광주시장배'), findsWidgets);
      expect(find.text('기록을 불러오지 못했습니다.'), findsNothing);
      // 순위 조회가 실패했으니(빈 목록 강등) 추이는 시도조차 하지 않는다.
      expect(api.playerRankingHistoryCalls, 0);
    });

    testWidgets('순위(보조) 조회가 pending 이어도 전적은 먼저 렌더된다', (tester) async {
      final rankingsPending = Completer<List<OrgRankingRow>>();
      final api = _FakeOrgRecordApi(
        link: const {'org_code': _kOrgCode, 'org_player_id': _kOrgPlayerId},
        results: [_result()],
        rankingsPending: rankingsPending,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const MyRecordScreen(orgCode: _kOrgCode),
          ),
        ),
      );
      // pumpAndSettle 은 안 쓴다 — aux(순위) 조회가 절대 안 끝나므로 core(전적)만
      // 뜨는 걸 확인할 만큼만 프레임을 민다.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('광주시장배'), findsWidgets);
      expect(find.text('기록을 불러오지 못했습니다.'), findsNothing);

      // 테스트 종료 후 미완료 Future 로 인한 pending timer 누수를 막는다.
      rankingsPending.complete(const []);
      await tester.pump();
    });
  });

  group('myRecordForOrgProvider — 링크 1회 조회(Fix 2)', () {
    testWidgets('링크를 한 번만 조회하고 그 값으로 전적·순위를 직접 조회한다', (tester) async {
      final api = await _pumpOrgScreen(
        tester,
        link: const {'org_code': _kOrgCode, 'org_player_id': _kOrgPlayerId},
        results: [_result()],
        rankings: [_ranking()],
        snapshots: [_snapshot()],
      );

      expect(api.confirmedLinkCalls, 1);
      expect(api.playerResultsCalls, 1);
      expect(api.playerRankingsCalls, 1);
      expect(find.text('광주시장배'), findsWidgets);
      // myPlayerResults/myCurrentRankings 를 불렀다면 fake 가 StateError 를
      // 던져 pumpAndSettle 단계에서 이미 실패했을 것이다.
    });

    testWidgets('링크가 없으면 ConnectPrompt 를 보여준다', (tester) async {
      await _pumpOrgScreen(tester, link: null);

      expect(find.text('협회 기록을 가져오세요'), findsOneWidget);
    });
  });

  group('org 쿼리 검증(Fix 3)', () {
    test('잘못된 org 는 라우터 단계에서 null 로 강등된다', () {
      expect(validatedRankingOrgCode('xx'), null);
      expect(validatedRankingOrgCode('jn '), 'jn');
    });

    testWidgets('강등된(null) orgCode 로 열면 기존 기본 화면으로 동작한다', (tester) async {
      // 'xx' 는 validatedRankingOrgCode 를 거치면 null 이 된다 — 라우터가
      // MyRecordScreen 에 org 를 아예 넘기지 않는 것과 같다. 이때 화면은
      // myRecordForOrgProvider 가 아니라 기존 fallback 체인(myConfirmedLinkProvider
      // 등)을 쓴다.
      final invalidatedOrg = validatedRankingOrgCode('xx');
      expect(invalidatedOrg, null);

      final api = _FakeOrgRecordApi(
        link: const {'org_code': _kOrgCode, 'org_player_id': _kOrgPlayerId},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: MyRecordScreen(orgCode: invalidatedOrg),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 기본 체인은 myConfirmedLink(orgCode: null) 을 부른다 — myRecordForOrgProvider
      // 라면 던졌을 myPlayerResults/myCurrentRankings 호출까지 정상적으로 거친다.
      expect(find.text('기록을 불러오지 못했습니다.'), findsNothing);
      expect(find.byType(ConnectPrompt), findsNothing);
    });
  });
}
