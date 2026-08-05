import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/rankings/rankings_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

OrgRankingRow _row({
  required int rank,
  required String name,
  required int points,
  String? orgPlayerId,
}) {
  return OrgRankingRow(
    orgCode: 'gj',
    divisionCode: 'gj_m_gold',
    rank: rank,
    playerName: name,
    rankPoints: points,
    totalPoints: points,
    orgPlayerId: orgPlayerId,
    clubRaw: '어등산/',
  );
}

/// 화면 통합용 — _load() 가 실제로 쓰는 네 조회만 갈아끼운다.
/// (단위 테스트가 판정 함수를 고정해도, 화면이 그 판정을 안 쓰면 소용없다.)
class _FakeRankingApi extends ApiService {
  _FakeRankingApi({required this.rows, required this.links})
      : super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'qa-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<OrgRankingRow> rows;
  final List<Map<String, dynamic>> links;

  @override
  Future<List<OrgRankingRow>> orgRankings({
    required String orgCode,
    required String divisionCode,
  }) async =>
      rows;

  @override
  Future<List<Map<String, dynamic>>> orgPlayerLinks(String orgCode) async =>
      links;

  @override
  Future<List<OrgRankingRow>> myRankingCandidates() async => const [];

  @override
  Future<List<UserTennisOrg>> myTennisOrgs() async => [
        UserTennisOrg(
          org: 'gj',
          division: 'default',
          divisionCodes: const ['gj_m_gold'],
        ),
      ];

  @override
  Future<List<PlayerResult>> myPlayerResults() async => const [];
}

const _kTestUserId = 'me-uuid';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<OrgRankingRow> rows,
  required List<Map<String, dynamic>> links,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(
          _FakeRankingApi(rows: rows, links: links),
        ),
        currentUserProvider.overrideWithValue(
          User(
            id: _kTestUserId,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-08-05T00:00:00Z',
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const RankingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('순위표 행이 렌더링된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: null,
      ),
    );

    expect(find.text('김평화'), findsOneWidget);
    expect(find.text('이기영'), findsOneWidget);
  });

  testWidgets('출처 표기가 항상 보인다', (tester) async {
    await _pump(tester, const RankingSourceNotice(orgLabel: '광주광역시테니스협회'));

    expect(find.textContaining('광주광역시테니스협회'), findsOneWidget);
    expect(find.textContaining('협회 공표가 우선'), findsOneWidget);
    // 미가입자도 자기 이름을 발견하는 유일한 자리라, 삭제·정정 요청 연락처가
    // 상시 노출돼야 한다(privacy-policy.html 7항과 같은 주소).
    expect(find.textContaining('삭제'), findsOneWidget);
    expect(find.textContaining('play@jyoungad.kr'), findsOneWidget);
    // fetchedAt 을 안 주면 기준일 줄은 생략된다(로드 전·행 없음 케이스).
    expect(find.textContaining('기준'), findsNothing);
  });

  testWidgets('기준일이 주어지면 표시된다', (tester) async {
    // 연초 협회 포인트 리셋 등으로 미러가 갱신을 건너뛰면 화면이 옛 데이터를
    // "현재"처럼 보여줄 위험이 있다 — fetched_at 표시가 그 방지책이다.
    await _pump(
      tester,
      RankingSourceNotice(
        orgLabel: '광주광역시테니스협회',
        fetchedAt: DateTime.utc(2026, 8, 3, 21),
      ),
    );

    expect(find.textContaining('기준'), findsOneWidget);
  });

  testWidgets('내 계정과 연결된 행은 강조된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'vudghk2116'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'lkybks'),
        ],
        linkedOrgPlayerId: 'vudghk2116',
      ),
    );

    expect(find.byKey(const ValueKey('ranking-row-mine')), findsOneWidget);
  });

  test('검색어는 이름과 소속 둘 다에서 부분일치로 거른다', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
      _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
    ];

    expect(filterRankingRows(rows, '').length, 2);
    expect(filterRankingRows(rows, '  ').length, 2);
    expect(filterRankingRows(rows, '평화').single.playerName, '김평화');
    // 소속(clubRaw) 도 검색 대상 — 같은 클럽 사람을 한 번에 본다.
    expect(filterRankingRows(rows, '어등산').length, 2);
    expect(filterRankingRows(rows, '없는이름'), isEmpty);
  });

  group('신청 가능한 행 계산', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
      _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
      _row(rank: 3, name: '박무명', points: 100), // 협회 아이디 없는 행
    ];
    const me = 'me-uuid';

    Set<String> compute(List<Map<String, dynamic>> links, {bool here = true}) =>
        computeClaimableIds(
          rows: rows,
          links: links,
          myUserId: me,
          registeredHere: here,
        );

    test('등록한 부서가 아니면 아무 행도 신청할 수 없다', () {
      expect(compute(const [], here: false), isEmpty);
    });

    test('협회 아이디가 없는 행은 신청 대상이 아니다', () {
      expect(compute(const []), {'a', 'b'});
    });

    test('남이 이미 확정한 선수는 빠진다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), {'b'});
    });

    test('남이 신청 중(pending)인 선수는 아직 내가 신청할 수 있다', () {
      // 승인 전이라 주인이 정해지지 않았다 — 경합은 관리자 승인 큐가 가린다.
      final links = [
        {'org_player_id': 'a', 'status': 'pending', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), {'a', 'b'});
    });

    test('내가 이미 신청한(pending) 선수는 빠진다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'pending', 'user_id': me},
      ];
      expect(compute(links), {'b'});
    });

    test('반려(rejected)된 내 신청도 다시 뜨지 않는다', () {
      // unique(org_code, org_player_id, user_id) 가 상태를 안 가려서 재신청 INSERT 가
      // 반드시 실패한다 — 버튼이 다시 뜨면 사용자는 이유 모를 에러만 보게 된다.
      final links = [
        {'org_player_id': 'a', 'status': 'rejected', 'user_id': me},
      ];
      expect(compute(links), {'b'});
    });

    // 실제로는 RLS(org_player_links_read)가 남의 rejected 를 주지 않아 이 링크는
    // 화면에 오지 않는다. 정책이 바뀌어 들어오더라도 남의 반려가 내 신청을
    // 막지는 않아야 하므로 함수 차원에서 고정해 둔다.
    test('남이 반려당한 선수는 여전히 내가 신청할 수 있다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'rejected', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), {'a', 'b'});
    });
  });

  testWidgets('신청 가능한 행에만 본인 버튼이 붙는다', (tester) async {
    OrgRankingRow? claimed;
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
        ],
        linkedOrgPlayerId: null,
        claimableOrgPlayerIds: const {'a'},
        onClaim: (row) => claimed = row,
      ),
    );

    expect(find.text('본인'), findsOneWidget);
    await tester.tap(find.text('본인'));
    expect(claimed?.orgPlayerId, 'a');
  });

  testWidgets('신청 자격이 없으면(등록 부서 밖) 버튼이 하나도 안 뜬다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [_row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a')],
        linkedOrgPlayerId: null,
        onClaim: (_) {},
      ),
    );

    expect(find.text('본인'), findsNothing);
  });

  group('화면이 판정을 실제로 반영한다', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
      _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
    ];

    testWidgets('검색어를 넣으면 그 행만 남는다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const []);
      expect(find.text('이기영'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '평화');
      await tester.pumpAndSettle();

      expect(find.text('김평화'), findsOneWidget);
      expect(find.text('이기영'), findsNothing);
    });

    testWidgets('반려된 내 신청의 선수에는 본인 버튼이 안 붙는다', (tester) async {
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [
          {
            'org_player_id': 'a',
            'status': 'rejected',
            'user_id': _kTestUserId,
          },
        ],
      );

      // 등록 부서(gj_m_gold)라 b 에는 버튼이 있고, 반려된 a 에는 없어야 한다.
      expect(find.text('본인'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '평화');
      await tester.pumpAndSettle();
      expect(find.text('본인'), findsNothing);
    });
  });

  testWidgets('후보가 있으면 클레임 카드가 뜬다', (tester) async {
    await _pump(
      tester,
      RankingClaimPrompt(
        candidate: _row(
          rank: 12,
          name: '김평화',
          points: 340,
          orgPlayerId: 'vudghk2116',
        ),
        onClaim: () {},
      ),
    );

    expect(find.textContaining('본인'), findsOneWidget);
  });
}
