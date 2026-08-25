import 'package:allround/models/org_ranking.dart';
import 'package:allround/models/org_ranking_snapshot.dart';
import 'package:allround/models/player_result.dart';
import 'package:allround/models/tournament.dart';
import 'package:allround/screens/rankings/player_history_sheet.dart';
import 'package:allround/screens/rankings/rankings_screen.dart';
import 'package:allround/services/api.dart';
import 'package:allround/state/providers.dart';
import 'package:allround/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    this.history,
    this.myRankings = const [],
    this.playerRankingsThrows = false,
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
  final PlayerHistory? history;
  final List<OrgRankingRow> myRankings;
  final bool playerRankingsThrows;

  /// 마지막으로 조회한 협회·부서 — 드롭다운 변경이 실제 재조회로 이어지는지 검증용.
  String? lastOrgCode;
  String? lastDivisionCode;
  String? lastPlayerRankingsOrgCode;

  @override
  Future<List<OrgRankingRow>> orgRankings({
    required String orgCode,
    required String divisionCode,
  }) async {
    lastOrgCode = orgCode;
    lastDivisionCode = divisionCode;
    return rows;
  }

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

  @override
  Future<PlayerHistory> playerHistory(OrgRankingRow player) async {
    return history ??
        PlayerHistory(
          results: const [],
          fetchedAt: DateTime.utc(2026, 8, 9),
          isComplete: true,
          wasCached: true,
        );
  }

  @override
  Future<List<OrgRankingSnapshot>> playerRankingHistory({
    required String orgCode,
    required String divisionCode,
    required String orgPlayerId,
  }) async =>
      const [];

  @override
  Future<List<OrgRankingRow>> playerRankings({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    lastPlayerRankingsOrgCode = orgCode;
    if (playerRankingsThrows) throw Exception('boom');
    return myRankings;
  }
}

const _kTestUserId = 'me-uuid';

Future<_FakeRankingApi> _pumpScreen(
  WidgetTester tester, {
  required List<OrgRankingRow> rows,
  required List<Map<String, dynamic>> links,
  List<OrgRankingRow> candidates = const [],
  String myName = '김평화',
  List<UserTennisOrg>? myOrgs,
  PlayerHistory? history,
  List<OrgRankingRow> myRankings = const [],
  bool playerRankingsThrows = false,
}) async {
  final api = _FakeRankingApi(
    rows: rows,
    links: links,
    candidates: candidates,
    myName: myName,
    myOrgs: myOrgs,
    history: history,
    myRankings: myRankings,
    playerRankingsThrows: playerRankingsThrows,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(api),
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
  return api;
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
  group('협회 드롭다운', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
    ];

    testWidgets('세그먼트 대신 드롭다운이 뜨고, 부서 드롭다운과 한 줄에 나란하다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const []);

      // 협회가 계속 추가될 예정이라 세그먼트는 확장이 안 된다 — 드롭다운으로 교체.
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.text('광주협회'), findsOneWidget);
      expect(find.text('협회'), findsOneWidget); // labelText
      expect(find.text('부서'), findsOneWidget); // labelText
    });

    testWidgets('협회를 바꾸면 그 협회의 첫 부서로 다시 조회한다', (tester) async {
      final api = await _pumpScreen(tester, rows: rows, links: const []);

      await tester.tap(find.text('광주협회'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전남협회').last);
      await tester.pumpAndSettle();

      // 부서 items 가 통째로 바뀌어도 크래시 없이(ValueKey 재생성) 첫 부서로 리셋.
      expect(api.lastOrgCode, 'jn');
      expect(api.lastDivisionCode, 'jn_m_gold');
    });
  });

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

  testWidgets('순위표 각 행에 아바타가 보인다 (탭 대상이 시각적으로 드러나야 한다)', (tester) async {
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

    expect(find.byType(CircleAvatar), findsNWidgets(2));
  });

  testWidgets('이름이 공백뿐이면 아바타 이니셜이 물음표로 대체된다', (tester) async {
    await _pump(
      tester,
      RankingList(
        rows: [_row(rank: 1, name: '  ', points: 100, orgPlayerId: 'a')],
        linkedOrgPlayerId: null,
      ),
    );

    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('선수 행을 누르면 대회 이력을 보여준다', (tester) async {
    final history = PlayerHistory(
      results: [
        PlayerResult(
          orgCode: 'gj',
          orgPlayerId: 'a',
          tournamentName: '광주시장배',
          playedOn: DateTime(2026, 5),
          resultRaw: '1',
          resultRound: 1,
          points: 1000,
          eventRaw: '골드부',
        ),
      ],
      fetchedAt: DateTime.utc(2026, 8, 9),
      isComplete: true,
      wasCached: false,
    );
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
    ];
    await _pumpScreen(tester, rows: rows, links: const [], history: history);

    await tester.tap(find.text('김평화').first);
    await tester.pumpAndSettle();

    expect(find.text('선수 기록'), findsOneWidget);
    expect(find.text('광주시장배'), findsOneWidget);
    expect(find.text('우승'), findsOneWidget);
  });

  testWidgets('선수 기록 시트는 320px 200% 글자에서도 긴 협회 원문을 모두 표시한다',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final player = _row(
      rank: 1,
      name: '아주긴이름의테니스선수',
      points: 2649,
      orgPlayerId: 'a',
    );
    const rawResult = '예선탈락(1회전 세트스코어 0:2 패배, 재경기 없음)';
    final history = PlayerHistory(
      results: [
        PlayerResult(
          orgCode: 'gj',
          orgPlayerId: 'a',
          tournamentName: '아주 긴 이름의 광주광역시 전국 생활체육 테니스대회',
          playedOn: DateTime(2026, 5),
          resultRaw: rawResult,
          points: 0,
          eventRaw: '남자골드부 개인복식',
        ),
      ],
      fetchedAt: DateTime.utc(2026, 8, 9),
      isComplete: true,
      wasCached: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: PlayerHistorySheet(
              player: player,
              load: () async => history,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(rawResult),
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('player-history-list')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 12,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(rawResult), findsOneWidget);
    final resultText = tester.widget<Text>(find.text(rawResult));
    expect(resultText.maxLines, isNull);
    expect(resultText.overflow, isNot(TextOverflow.ellipsis));
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

    // 우선순위 고정(codex 리뷰 2026-08-18). 후보 카드·'확인 중입니다'는 부서가
    // 아니라 협회 단위로 뜬다 — 화면 기본 부서가 gj_m_gold 라 부서로 좁히면
    // 남자일반부 후보를 가진 사람이 탭을 옮기기 전엔 카드를 못 본다.
    // 진행 중인 신청 소식이 "여긴 네 부서가 아니야"보다 먼저다.
    testWidgets('같은 협회에 진행 중인 신청이 있으면 그 소식이 먼저다', (tester) async {
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [
          {'org_player_id': 'a', 'status': 'pending', 'user_id': _kTestUserId},
        ],
        myOrgs: [
          UserTennisOrg(
            org: 'gj',
            division: 'default',
            divisionCodes: const ['gj_m_general'],
          ),
        ],
      );

      expect(find.text('확인 중입니다'), findsOneWidget);
      expect(find.textContaining('내가 등록한 부서가 아니라'), findsNothing);
    });

    // 단 협회 등록이 0개면 등록 안내가 이긴다. 등록을 지워도 pending 은
    // 남으므로(org_player_links 는 user_tennis_orgs 와 별개 테이블),
    // 순서가 반대면 '확인 중입니다'가 등록 안내를 영구히 가린다
    // (codex 리뷰 2026-08-18).
    testWidgets('협회 등록을 지운 뒤 pending 이 남아 있어도 등록 안내가 이긴다', (tester) async {
      await _pumpScreen(
        tester,
        rows: rows,
        links: const [
          {'org_player_id': 'a', 'status': 'pending', 'user_id': _kTestUserId},
        ],
        myOrgs: const [],
      );

      expect(find.widgetWithText(TextButton, '등록하러 가기'), findsOneWidget);
      expect(find.text('확인 중입니다'), findsNothing);
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

  group('내 기록 요약 카드', () {
    final rows = [
      _row(rank: 1, name: '김평화', points: 2649, orgPlayerId: 'a'),
    ];
    const confirmedLinks = [
      {'org_player_id': 'a', 'status': 'confirmed', 'user_id': _kTestUserId},
    ];

    testWidgets('확정 연결이 있으면 요약 카드가 뜨고 "내 기록 보기" 링크는 없다', (tester) async {
      await _pumpScreen(
        tester,
        rows: rows,
        links: confirmedLinks,
        myRankings: [
          _row(rank: 3, name: '김평화', points: 2649, orgPlayerId: 'a'),
        ],
      );

      expect(find.byKey(const ValueKey('my-ranking-summary-card')), findsOneWidget);
      // 부서(골드부)·순위(3위)·누적 포인트(2,649P)가 한 카드에 보인다.
      expect(find.textContaining('골드부 3위'), findsOneWidget);
      expect(find.textContaining('2,649P'), findsOneWidget);
      // 진입점은 카드로 대체됐다 — 링크는 제거.
      expect(find.text('내 기록 보기'), findsNothing);
    });

    testWidgets('연결은 있는데 공표 표에 내 행이 없어도 카드는 뜬다', (tester) async {
      // 연초 협회 포인트 리셋 등으로 표가 비어도, 링크를 없앤 자리라 이 카드가
      // /rankings/me 로 가는 유일한 진입점이다 — 사라지면 기록 화면이 고아가 된다.
      await _pumpScreen(tester, rows: rows, links: confirmedLinks);

      expect(find.byKey(const ValueKey('my-ranking-summary-card')), findsOneWidget);
      expect(find.text('공표된 순위 없음'), findsOneWidget);
    });

    testWidgets('내 기록 요약 조회가 실패해도 순위표는 정상적으로 뜬다', (tester) async {
      // 부가 기능(요약 카드)이 핵심 기능(공개 순위표)을 죽이면 안 된다 —
      // playerRankings() 가 예외를 던져도 _load() 전체가 실패해서는 안 된다.
      await _pumpScreen(
        tester,
        rows: rows,
        links: confirmedLinks,
        playerRankingsThrows: true,
      );

      expect(find.text('김평화'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-ranking-summary-card')), findsOneWidget);
      expect(find.text('공표된 순위 없음'), findsOneWidget);
    });

    testWidgets('확정 연결이 없어도 카드가 뜨고, 그 아래 기존 연결 유도도 함께 뜬다', (tester) async {
      // "이 화면도 너무하지 않아?" 피드백 — 미연결 협회라고 카드 자체를 숨기지
      // 않는다. 대신 탭 불가·안내 문구로 상태를 표시하고, 기존 유도 체인은
      // 카드 아래 그대로 유지한다.
      await _pumpScreen(tester, rows: rows, links: const [], myOrgs: const []);

      expect(find.byKey(const ValueKey('my-ranking-summary-card')), findsOneWidget);
      expect(find.textContaining('전적이 없거나 확인되지 않았습니다'), findsOneWidget);
      // 탭 불가 상태라 거짓 어포던스인 화살표는 없어야 한다.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.textContaining('소속 협회·부서를 등록하면'), findsOneWidget);
    });

    testWidgets('미연결 카드는 탭해도 아무 데도 가지 않는다', (tester) async {
      // AppCard 는 onTap 이 null 이면 InkWell 자체를 만들지 않는다 — 탭해도
      // 반응이 없어야 정상.
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const RankingsScreen()),
          GoRoute(
            path: '/rankings/me',
            builder: (_, __) => const Scaffold(body: Text('내 기록 화면')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiProvider.overrideWithValue(
              _FakeRankingApi(rows: rows, links: const [], myOrgs: const []),
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
          child:
              MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('my-ranking-summary-card')));
      await tester.pumpAndSettle();

      expect(find.text('내 기록 화면'), findsNothing);
    });

    testWidgets('협회를 바꾸면 내 기록도 그 협회 기준으로 다시 조회한다', (tester) async {
      final api = await _pumpScreen(
        tester,
        rows: rows,
        links: confirmedLinks,
        myRankings: [
          _row(rank: 3, name: '김평화', points: 2649, orgPlayerId: 'a'),
        ],
      );
      expect(api.lastPlayerRankingsOrgCode, 'gj');

      await tester.tap(find.text('광주협회'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전남협회').last);
      await tester.pumpAndSettle();

      // 협회별로 내 기록이 다를 수 있다 — 카드 데이터도 새 협회로 재조회돼야 한다.
      expect(api.lastPlayerRankingsOrgCode, 'jn');
    });

    testWidgets('카드를 탭하면 /rankings/me 로 간다', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const RankingsScreen()),
          GoRoute(
            path: '/rankings/me',
            builder: (_, __) => const Scaffold(body: Text('내 기록 화면')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiProvider.overrideWithValue(
              _FakeRankingApi(
                rows: rows,
                links: confirmedLinks,
                myRankings: [
                  _row(rank: 3, name: '김평화', points: 2649, orgPlayerId: 'a'),
                ],
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
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('my-ranking-summary-card')));
      await tester.pumpAndSettle();

      expect(find.text('내 기록 화면'), findsOneWidget);
    });
  });
}
