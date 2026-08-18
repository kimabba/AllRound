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

/// 기본 등록 상태 — 광주협회 남자골드부. 화면 기본 선택과 같아 registeredHere 가 참이다.
/// UserTennisOrg 는 const 생성자가 아니라 최종 필드로 둔다.
final _kDefaultMyOrgs = [
  UserTennisOrg(
    org: 'gj',
    division: 'default',
    divisionCodes: const ['gj_m_gold'],
  ),
];

/// 화면 통합용 — _load() 가 실제로 쓰는 네 조회만 갈아끼운다.
/// (단위 테스트가 판정 함수를 고정해도, 화면이 그 판정을 안 쓰면 소용없다.)
class _FakeRankingApi extends ApiService {
  _FakeRankingApi({
    required this.rows,
    required this.links,
    this.candidates = const [],
    this.myName = '김평화',
    List<UserTennisOrg>? myOrgs,
  })  : myOrgs = myOrgs ?? _kDefaultMyOrgs,
        super(
          SupabaseClient(
            'http://127.0.0.1:54321',
            'qa-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<OrgRankingRow> rows;
  final List<Map<String, dynamic>> links;
  final List<OrgRankingRow> candidates;
  final String myName;
  final List<UserTennisOrg> myOrgs;

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
  Future<List<OrgRankingRow>> myRankingCandidates() async => candidates;

  @override
  Future<List<UserTennisOrg>> myTennisOrgs() async => myOrgs;

  @override
  Future<UserProfile?> myProfile() async => UserProfile(name: myName);

  @override
  Future<List<PlayerResult>> myPlayerResults() async => const [];
}

const _kTestUserId = 'me-uuid';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<OrgRankingRow> rows,
  required List<Map<String, dynamic>> links,
  List<OrgRankingRow> candidates = const [],
  String myName = '김평화',
  List<UserTennisOrg>? myOrgs,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(
          _FakeRankingApi(
            rows: rows,
            links: links,
            candidates: candidates,
            myName: myName,
            myOrgs: myOrgs,
          ),
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

    // 이름이 같은 행만 신청할 수 있다 — 아래 대부분의 케이스는 '김평화'(id a) 기준.
    Set<String> compute(
      List<Map<String, dynamic>> links, {
      bool here = true,
      String myName = '김평화',
    }) =>
        computeClaimableIds(
          rows: rows,
          links: links,
          myUserId: me,
          myName: myName,
          registeredHere: here,
        );

    test('등록한 부서가 아니면 아무 행도 신청할 수 없다', () {
      expect(compute(const [], here: false), isEmpty);
    });

    test('협회 아이디가 없는 행은 신청 대상이 아니다', () {
      // '박무명'(id 없음)은 이름이 같아도 대상이 될 수 없다.
      expect(compute(const [], myName: '박무명'), isEmpty);
    });

    test('이름이 같은 행만 신청할 수 있다', () {
      expect(compute(const []), {'a'});
      expect(compute(const [], myName: '이기영'), {'b'});
      expect(compute(const [], myName: '없는사람'), isEmpty);
    });

    test('가입 이름이 비어 있으면 아무것도 신청할 수 없다', () {
      expect(compute(const [], myName: ''), isEmpty);
      // 정책이 글자 그대로 비교하므로 앞뒤 여백은 앱에서도 불일치로 본다 —
      // 앱만 관대하면 버튼은 보이는데 서버가 거부한다.
      expect(compute(const [], myName: ' 김평화 '), isEmpty);
      expect(
        computeClaimableIds(
          rows: rows,
          links: const [],
          myUserId: me,
          myName: null,
          registeredHere: true,
        ),
        isEmpty,
      );
    });

    test('이 협회에 내 확정 연결이 있으면 다른 선수도 신청할 수 없다', () {
      // 협회당 유저 1명 1선수(org_player_links_confirmed_user_key). 받아두면
      // 관리자가 승인할 수 없는 대기 건만 쌓인다.
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': me},
      ];
      expect(compute(links), isEmpty);
    });

    test('남이 이미 확정한 선수는 빠진다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), isEmpty);
    });

    test('남이 신청 중(pending)인 선수는 아직 내가 신청할 수 있다', () {
      // 승인 전이라 주인이 정해지지 않았다 — 경합은 관리자 승인 큐가 가린다.
      final links = [
        {'org_player_id': 'a', 'status': 'pending', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), {'a'});
    });

    test('내가 이미 신청한(pending) 선수는 빠진다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'pending', 'user_id': me},
      ];
      expect(compute(links), isEmpty);
    });

    test('반려(rejected)된 내 신청도 다시 뜨지 않는다', () {
      // unique(org_code, org_player_id, user_id) 가 상태를 안 가려서 재신청 INSERT 가
      // 반드시 실패한다 — 버튼이 다시 뜨면 사용자는 이유 모를 에러만 보게 된다.
      final links = [
        {'org_player_id': 'a', 'status': 'rejected', 'user_id': me},
      ];
      expect(compute(links), isEmpty);
    });

    // 실제로는 RLS(org_player_links_read)가 남의 rejected 를 주지 않아 이 링크는
    // 화면에 오지 않는다. 정책이 바뀌어 들어오더라도 남의 반려가 내 신청을
    // 막지는 않아야 하므로 함수 차원에서 고정해 둔다.
    test('남이 반려당한 선수는 여전히 내가 신청할 수 있다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'rejected', 'user_id': 'other-uuid'},
      ];
      expect(compute(links), {'a'});
    });
  });

  group('이의신청 가능한 행 계산', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
      _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
    ];
    const me = 'me-uuid';

    Set<String> dispute(
      List<Map<String, dynamic>> links, {
      bool here = true,
      String myName = '김평화',
    }) =>
        computeDisputableIds(
          rows: rows,
          links: links,
          myUserId: me,
          myName: myName,
          registeredHere: here,
        );

    Set<String> claim(List<Map<String, dynamic>> links) => computeClaimableIds(
          rows: rows,
          links: links,
          myUserId: me,
          myName: '김평화',
          registeredHere: true,
        );

    test('남이 확정한 선수에만 붙는다 — 신청 버튼이 사라지는 자리다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(dispute(links), {'a'});
      // 두 집합은 겹치지 않는다 — 한 줄에 버튼이 둘 뜨면 안 된다.
      expect(claim(links), isEmpty);
    });

    test('빈 자리(주인 없음)에는 붙지 않는다 — 그건 일반 신청이다', () {
      expect(dispute(const []), isEmpty);
      expect(claim(const []), {'a'});
    });

    test('남이 신청 중(pending)일 뿐이면 붙지 않는다', () {
      // 아직 주인이 없다 — 일반 신청으로 경합하면 된다.
      final links = [
        {'org_player_id': 'a', 'status': 'pending', 'user_id': 'other-uuid'},
      ];
      expect(dispute(links), isEmpty);
      expect(claim(links), {'a'});
    });

    test('내가 이미 그 선수에 신청·반려 이력이 있으면 빠진다', () {
      // unique(org_code, org_player_id, user_id) 가 상태를 안 가려서 재신청이
      // 반드시 실패한다 — 버튼이 뜨면 이유 모를 에러만 본다.
      for (final mineStatus in ['pending', 'rejected']) {
        final links = [
          {
            'org_player_id': 'a',
            'status': 'confirmed',
            'user_id': 'other-uuid',
          },
          {'org_player_id': 'a', 'status': mineStatus, 'user_id': me},
        ];
        expect(dispute(links), isEmpty, reason: mineStatus);
      }
    });

    test('이 협회에 내 확정 연결이 있으면 아무 행도 다툴 수 없다', () {
      // has_confirmed_org_link() 가 INSERT 를 거부한다.
      final links = [
        {'org_player_id': 'b', 'status': 'confirmed', 'user_id': me},
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(dispute(links), isEmpty);
    });

    test('이름이 다르면 다툴 수 없다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(dispute(links, myName: '없는사람'), isEmpty);
      // 정책이 글자 그대로 비교한다 — 앞뒤 여백도 불일치다.
      expect(dispute(links, myName: ' 김평화 '), isEmpty);
    });

    test('등록한 부서가 아니면 다툴 수 없다', () {
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
      ];
      expect(dispute(links, here: false), isEmpty);
    });

    test('로그인 전(myUserId=null)에는 두 함수 다 아무 행도 내지 않는다', () {
      // 내 링크를 못 알아봐 전부 남의 것으로 취급하게 된다. 서버는 어차피
      // user_id = auth.uid() 로 거부한다(codex 리뷰 2026-08-18).
      final links = [
        {'org_player_id': 'a', 'status': 'confirmed', 'user_id': 'other-uuid'},
        {'org_player_id': 'b', 'status': 'confirmed', 'user_id': me},
      ];
      for (final compute in [computeDisputableIds, computeClaimableIds]) {
        expect(
          compute(
            rows: rows,
            links: links,
            myUserId: null,
            myName: '김평화',
            registeredHere: true,
          ),
          isEmpty,
        );
      }
    });
  });

  // 본인 연결 진입이 0건인 이유 중 하나 — 등록 안 한 부서를 보면 버튼만
  // 조용히 사라지고 설명이 없었다(2026-08-18 실측: 27명 중 20명이 협회 미등록).
  group('등록 안 한 부서 안내', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
    ];

    testWidgets('협회를 하나도 등록 안 했으면 등록을 권하고 버튼을 준다', (tester) async {
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [],
        myOrgs: const [],
      );

      expect(find.textContaining('소속 협회·부서를 등록하면'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '등록하러 가기'), findsOneWidget);
    });

    testWidgets('등록은 했지만 다른 부서를 보는 중이면 버튼을 주지 않는다', (tester) async {
      // "등록하러 가라"가 틀린 조언인 자리다 — 그 협회 랭커가 아닌 사람이
      // 자기 부서가 아닌 것을 등록하게 만든다.
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [],
        myOrgs: [
          UserTennisOrg(
            org: 'gj',
            division: 'default',
            // 화면 기본 선택은 gj_m_gold 라 여기는 "내 부서가 아님"이 된다.
            divisionCodes: const ['gj_m_general'],
          ),
        ],
      );

      expect(find.textContaining('내가 등록한 부서가 아니라'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '등록하러 가기'), findsNothing);
    });

    testWidgets('등록한 부서를 보는 중이면 이 안내가 안 뜬다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const []);

      expect(find.textContaining('소속 협회·부서를 등록하면'), findsNothing);
      expect(find.textContaining('내가 등록한 부서가 아니라'), findsNothing);
    });
  });

  testWidgets('이미 주인이 있는 줄에는 이의신청 버튼이 붙는다', (tester) async {
    OrgRankingRow? disputed;
    await _pump(
      tester,
      RankingList(
        rows: [
          _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
          _row(rank: 2, name: '이기영', points: 2562, orgPlayerId: 'b'),
        ],
        linkedOrgPlayerId: null,
        disputableOrgPlayerIds: const {'a'},
        onDispute: (row) => disputed = row,
      ),
    );

    expect(find.text('이의신청'), findsOneWidget);
    expect(find.text('본인'), findsNothing);
    await tester.tap(find.text('이의신청'));
    expect(disputed?.orgPlayerId, 'a');
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

    testWidgets('확정 연결이 있으면 행 버튼도 후보 카드도 안 뜬다', (tester) async {
      // 후보 카드는 행별 버튼과 다른 경로다. my_ranking_candidates() 는 "그 선수가
      // 확정됐는지"만 보므로, 같은 이름의 다른 선수를 후보로 낼 수 있다 —
      // 협회당 1명 1선수라 그 신청은 정책이 거부한다.
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [
          {
            'org_player_id': 'a',
            'status': 'confirmed',
            'user_id': _kTestUserId,
          },
        ],
        candidates: [
          _row(rank: 2, name: '김평화', points: 2562, orgPlayerId: 'b'),
        ],
      );

      expect(find.text('본인'), findsNothing);
      expect(find.text('신청'), findsNothing);
    });

    testWidgets('내 이름과 같은 행에만 본인 버튼이 붙는다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const []);
      // '김평화' 행에만 붙는다 — '이기영' 행에는 안 붙는다.
      expect(find.text('본인'), findsOneWidget);
    });

    testWidgets('이름이 명단에 없으면 버튼 대신 이유를 알려준다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const [], myName: '없는사람');

      expect(find.text('본인'), findsNothing);
      expect(find.textContaining('신청할 수 있는 줄이 없습니다'), findsOneWidget);
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

      // 내 이름과 같은 유일한 행(a)이 반려 상태라 신청할 행이 하나도 없다.
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
