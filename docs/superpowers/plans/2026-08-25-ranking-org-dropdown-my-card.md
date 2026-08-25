# 협회 랭킹 화면 개편 구현 계획

> 기준 브랜치: `feat/ranking-row-club-style` (행별 카드+아바타 적용 완료 상태). 이 위에 새 브랜치(예: `feat/ranking-org-dropdown-my-card`)를 만들어 구현한다.

## Goal

협회 랭킹 화면(`RankingsScreen`)의 상단 구조를 개편한다.

1. 광주/전남 세그먼트(`SegmentedButton`) → **협회 드롭다운**으로 교체하고, 기존 부서 드롭다운과 **한 줄 두 칸**으로 나란히 배치한다 (협회가 계속 추가돼도 UI가 버틴다).
2. **"내 기록 보기" 텍스트 링크를 제거**한다.
3. 드롭다운 바로 아래에 **내 기록 요약 카드**(내 순위·부서·누적 포인트)를 신설한다. 협회를 바꾸면 그 협회 기준으로 바뀌고, 탭하면 기존 `/rankings/me` 로 이동한다 (화면은 유지, 진입점만 카드로 교체).
4. 해당 협회에 confirmed 연결이 없으면 그 자리에 **기존 연결 유도/후보 카드 로직**(`_NotMyDivisionNotice`·`RankingClaimPrompt`·'확인 중입니다' 등)이 현행 우선순위 그대로 뜬다.
5. 검색창·출처 안내 배너·랭킹 목록은 내 기록 카드 **아래** 순서로 유지한다.

## Architecture

### 조사 결과 요약 (설계 근거)

- **협회 목록의 SSOT**: 화면은 이미 `kRankingDivisions.keys`(`app/lib/utils/grade_labels.dart:809`)를 쓴다. 이 const 는 "우리가 랭킹 미러를 가진 협회" 목록으로, 주석에 "미러를 늘릴 때 고칠 곳은 여기 하나다"라고 명시돼 있다. 라벨은 `tennisOrgShortLabel()` → `OrgCatalog`(DB `tennis_orgs` 기반, const 폴백)에서 온다. **드롭다운도 같은 소스를 그대로 쓴다** — 하드코딩 확장이 아니라 `kRankingDivisions` 에 협회를 추가하면 드롭다운 항목이 자동으로 늘어난다.
- **내 순위를 협회 단위로 아는 방법**: `_load()` 가 이미 `api.orgPlayerLinks(_orgCode)` 로 이 협회의 내 confirmed 연결(`linkedOrgPlayerId`)을 계산한다. 내 순위 행은 지금 보는 **부서**의 `orgRankings()` 결과에 없을 수 있으므로(내 부서 ≠ 보는 부서), `org_rankings` 를 `org_code + org_player_id` 로 조회하는 메서드가 필요하다. 이는 기존 `myCurrentRankings()`(`app/lib/services/ranking_api.dart:220`)와 **똑같은 쿼리 모양**이며, `org_rankings` 는 로그인 사용자 전체에게 이미 읽기가 열려 있다. → **서버/DB/RPC 변경 없음.** 클라이언트에 `playerRankings({orgCode, orgPlayerId})` 를 추가하고 `myCurrentRankings()` 가 위임하게 리팩터한다.
- **대표 부서 선정**: 한 선수가 여러 부서 랭킹에 오를 수 있다. 홈 등급 카드가 쓰는 `topDivisionRanking()`(`app/lib/state/providers.dart:173`, 협회 공표 순서 = 상위 부서 우선)을 그대로 재사용한다. `rankings_screen.dart` 는 이미 `providers.dart` 를 import 한다.
- **기존 안내 로직 위치**: 현재 후보 카드/'확인 중입니다'/`_NotMyDivisionNotice` 체인은 ListView 첫 자식으로 들어 있다(`rankings_screen.dart` build 내부, codex 리뷰 2026-08-18 의 우선순위 주석 포함). 이 체인을 `_buildStatusSlot()` 으로 추출해 "드롭다운 아래 고정 슬롯"으로 옮기고, confirmed 연결이 있으면 그 슬롯에 요약 카드를 대신 띄운다. **분기 우선순위는 바꾸지 않는다** (기존 주석·테스트가 지키는 순서 그대로).
- **테스트 의존성**: `app/test/rankings_screen_test.dart`(798줄)에 화면 통합 테스트가 있으나 `SegmentedButton` 이나 '내 기록 보기' 링크에 직접 의존하는 테스트는 **없다**. 다만 `_FakeRankingApi` 가 `_load()` 의 조회만 갈아끼우므로, `_load()` 에 새 API 호출이 추가되면 fake 에도 override 를 추가해야 한다(안 하면 실제 SupabaseClient 로 네트워크를 시도). `ranking_claims_test.dart` 는 관리자 승인 큐 테스트라 무관하다.
- **드롭다운 지뢰**: `tournament_submit_screen.dart:338` 주석이 경고하듯 `DropdownButtonFormField.initialValue` 는 최초값만 적용된다. 협회를 바꾸면 부서 items 가 통째로 바뀌는데 내부 value 가 옛 부서로 남으면 assert 가 터진다 → 부서 드롭다운에 `key: ValueKey(_orgCode)` 를 줘서 협회 변경 시 필드를 재생성한다.
- **한 가지 의도된 동작 변경**: 현재는 confirmed 연결 + (남아 있는) pending 이 공존하면 '확인 중입니다'가 뜰 수 있는데, 개편 후에는 confirmed 가 있으면 무조건 요약 카드가 이긴다. 연결이 완료된 사람에게 '확인 중'은 틀린 정보이므로 개선이다.

### 데이터 흐름 (개편 후)

```
_load()
 ├─ orgRankings(_orgCode, _divisionCode)        # 기존
 ├─ orgPlayerLinks(_orgCode) → linkedOrgPlayerId # 기존
 ├─ [신규] linkedOrgPlayerId != null 이면
 │    playerRankings(orgCode: _orgCode, orgPlayerId: linkedOrgPlayerId)
 │    → topDivisionRanking() → _RankingScreenData.myRanking
 └─ myRankingCandidates() / myTennisOrgs() / myProfile()  # 기존

build()
 ├─ Row [협회 드롭다운 | 부서 드롭다운]          # 세그먼트 대체
 ├─ FutureBuilder → _buildStatusSlot(data)       # 신규 고정 슬롯
 │    ├─ linked      → MyRankingSummaryCard (탭 → /rankings/me)
 │    └─ not linked  → 기존 안내 체인 그대로
 ├─ 검색 TextField / RankingSourceNotice          # 기존 유지
 └─ ListView (테이블 헤더 + RankingList)          # 안내 체인 빠짐
```

## Tech Stack

- Flutter (SDK ≥3.44) / Dart ^3.6, Riverpod 3, go_router, supabase_flutter 2, intl
- 테스트: `flutter_test` 위젯 테스트 (`ProviderScope` override + `_FakeRankingApi` 패턴)
- 서버/DB 변경: **없음** (기존 `org_rankings` 테이블·RLS 재사용. 새 RPC 불필요 — `myCurrentRankings()` 와 같은 쿼리를 협회 파라미터화한 것뿐이다)

## Global Constraints

- CI 는 warning 도 에러다: unused import/변수 금지, `flutter analyze` 클린 필수.
- `dynamic` 지양 — 기존 파일처럼 `Map<String, dynamic>` (Supabase row) 외에는 구체 타입 사용.
- 기존 파일의 주석 밀도·톤(왜 그런지 설명하는 한국어 주석)을 따른다.
- `myCurrentRankings()` 리팩터 시 **기존 정렬 순서를 바꾸지 않는다** — supabase-dart 의 `order()` 는 ascending 기본이 false 라 현재 `division_code` 내림차순이며, `myRankingHistoryProvider` 가 `rankings.first` 에 의존한다.
- 각 Task 는 독립 커밋: 실패 테스트 확인 → 구현 → 통과 확인 → 커밋.
- 테스트 실행: `cd /Users/ssfak/Documents/01-github/AllRound/app && flutter test test/rankings_screen_test.dart test/ranking_api_test.dart`, 분석: `flutter analyze`.

## File Structure

| 파일 | 책임 / 변경 내용 |
|---|---|
| `app/lib/services/ranking_api.dart` | **[수정]** `playerRankings({orgCode, orgPlayerId})` 신설, `myCurrentRankings()` 가 위임 |
| `app/lib/screens/rankings/rankings_screen.dart` | **[수정]** 세그먼트→협회 드롭다운(한 줄 두 칸), `MyRankingSummaryCard` 신설, `_buildStatusSlot()` 추출, '내 기록 보기' 링크 제거, `_RankingScreenData.myRanking` 추가 |
| `app/lib/state/providers.dart` | **[변경 없음]** `topDivisionRanking()` 재사용만 |
| `app/lib/utils/grade_labels.dart` | **[변경 없음]** `kRankingDivisions` / `tennisOrgShortLabel` 재사용만 |
| `app/test/ranking_api_test.dart` | **[수정]** `myCurrentRankings` 무연결 회귀 테스트 추가 |
| `app/test/rankings_screen_test.dart` | **[수정]** `_FakeRankingApi` 에 `playerRankings` override·`myRankings`·`lastOrgCode` 추가, 드롭다운/카드/네비게이션 테스트 추가 |

---

## Task 1 — 협회+선수 단위 랭킹 조회 API (`playerRankings`)

**Files**: `app/lib/services/ranking_api.dart`, `app/test/ranking_api_test.dart`

**Interfaces**
- Consumes: `supabase.from('org_rankings')` (기존 테이블·RLS), `OrgRankingRow.fromJson`
- Produces: `Future<List<OrgRankingRow>> playerRankings({required String orgCode, required String orgPlayerId})` — Task 3 의 `_load()` 가 소비

### Steps

- [ ] **1-1. 회귀 가드 테스트 추가** — `app/test/ranking_api_test.dart` 의 `main()` 에 추가 (리팩터 전후 동작 불변을 고정하는 테스트다. 신규 메서드 자체는 네트워크 없이 red-green 이 불가능해 위젯 테스트(Task 3)가 커버한다):

```dart
  test('연결이 없으면 myCurrentRankings 는 빈 목록이다(전체 순위를 긁지 않는다)', () async {
    final api = _unauthenticatedApi();
    expect(await api.myCurrentRankings(), isEmpty);
  });
```

- [ ] **1-2. 테스트 통과 확인**: `flutter test test/ranking_api_test.dart` (리팩터 전에도 통과해야 정상 — 기준선 확립)

- [ ] **1-3. 구현** — `app/lib/services/ranking_api.dart` 의 `myCurrentRankings()` 를 아래로 교체:

```dart
  /// 한 협회 안에서 특정 선수의 현재 순위(오른 부서 전부).
  ///
  /// 랭킹 화면의 "내 기록 요약"이 쓴다 — 지금 보는 부서와 내가 연결된 부서가
  /// 달라도 내 순위를 보여줘야 해서, 부서 필터 없이 협회+선수로 조회한다.
  /// 대표 부서 선정은 호출부가 topDivisionRanking 으로 한다.
  ///
  /// order 는 ascending 을 명시하지 않는다(= 내림차순, 파일 상단 주석 참조) —
  /// myCurrentRankings 가 위임하는데, myRankingHistoryProvider 가 결과의
  /// first 에 의존하고 있어 순서를 바꾸면 내 기록 화면의 추이 부서가 바뀐다.
  Future<List<OrgRankingRow>> playerRankings({
    required String orgCode,
    required String orgPlayerId,
  }) async {
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', orgCode)
        .eq('org_player_id', orgPlayerId)
        .order('division_code');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
  }

  /// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
  /// 한 선수가 여러 부서 랭킹에 오를 수 있어 목록으로 돌려준다.
  Future<List<OrgRankingRow>> myCurrentRankings() async {
    final link = await myConfirmedLink();
    if (link == null) return const [];
    return playerRankings(
      orgCode: link['org_code'] as String,
      orgPlayerId: link['org_player_id'] as String,
    );
  }
```

- [ ] **1-4. 통과 확인**: `flutter test test/ranking_api_test.dart && flutter analyze`

- [ ] **1-5. 커밋**:

```
feat(app): 협회+선수 단위 랭킹 조회 playerRankings 추가

myCurrentRankings 와 같은 쿼리를 협회 파라미터로 일반화하고 위임시킨다.
랭킹 화면의 "내 기록 요약 카드"(후속 작업)가 지금 보는 부서와 무관하게
그 협회에서의 내 순위를 얻는 데 쓴다. 서버/DB 변경 없음 — org_rankings
는 로그인 사용자 전체에게 이미 읽기가 열려 있다.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

---

## Task 2 — 협회 세그먼트 → 드롭다운 (부서 드롭다운과 한 줄 두 칸)

**Files**: `app/lib/screens/rankings/rankings_screen.dart`, `app/test/rankings_screen_test.dart`

**Interfaces**
- Consumes: `kRankingDivisions.keys` (미러 협회 SSOT), `tennisOrgShortLabel()` (OrgCatalog/DB 기반 라벨), 기존 `_changeOrg`/`_changeDivision`
- Produces: `Row[협회 Dropdown | 부서 Dropdown]` — Task 3 의 슬롯이 이 아래에 붙는다

### Steps

- [ ] **2-1. 실패 테스트 작성** — `app/test/rankings_screen_test.dart` 수정.

먼저 `_FakeRankingApi` 에 조회 기록 필드를 추가하고 `orgRankings` override 를 교체:

```dart
  /// 마지막으로 조회한 협회·부서 — 드롭다운 변경이 실제 재조회로 이어지는지 검증용.
  String? lastOrgCode;
  String? lastDivisionCode;

  @override
  Future<List<OrgRankingRow>> orgRankings({
    required String orgCode,
    required String divisionCode,
  }) async {
    lastOrgCode = orgCode;
    lastDivisionCode = divisionCode;
    return rows;
  }
```

`_pumpScreen` 이 fake 를 돌려주도록 시그니처를 바꾼다 (기존 호출부는 반환값을 안 쓰므로 그대로 동작):

```dart
Future<_FakeRankingApi> _pumpScreen(
  WidgetTester tester, {
  ...기존 파라미터 그대로...
}) async {
  final api = _FakeRankingApi(
    rows: rows,
    links: links,
    candidates: candidates,
    myName: myName,
    myOrgs: myOrgs,
    history: history,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(api),
        currentUserProvider.overrideWithValue(/* 기존 User(...) 그대로 */),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const RankingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}
```

새 테스트 그룹 추가:

```dart
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
```

- [ ] **2-2. 실패 확인**: `flutter test test/rankings_screen_test.dart` → `SegmentedButton findsNothing` 실패, '협회' labelText 부재 실패 확인

- [ ] **2-3. 구현** — `rankings_screen.dart` 의 `build()` 에서 세그먼트 Padding 블록과 부서 드롭다운 Padding 블록(현재 803~827행 부근) **둘을 삭제**하고 아래 하나로 교체:

```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              0,
            ),
            // 협회·부서를 한 줄 두 칸으로. 협회는 계속 추가될 예정이라
            // (kRankingDivisions 에 미러 협회를 넣으면 자동 반영) 세그먼트로는
            // 폭이 감당이 안 된다 — 부서와 같은 드롭다운 스타일로 맞춘다.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _orgCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '협회'),
                    items: [
                      for (final org in orgCodes)
                        DropdownMenuItem(
                          value: org,
                          child: Text(
                            tennisOrgShortLabel(org),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _changeOrg(v);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    // 협회가 바뀌면 부서 items 가 통째로 바뀐다. initialValue 는
                    // 최초 빌드에만 적용돼(tournament_submit_screen 의 회귀 주석
                    // 참조) 옛 부서 값이 남으면 assert 가 터진다 — 키로 필드를
                    // 재생성해 새 협회의 첫 부서로 리셋한다.
                    key: ValueKey('division-$_orgCode'),
                    initialValue: _divisionCode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '부서'),
                    items: [
                      for (final code in divisions)
                        DropdownMenuItem(
                            value: code, child: Text(divisionLabel(code))),
                    ],
                    onChanged: (v) {
                      if (v != null) _changeDivision(v);
                    },
                  ),
                ),
              ],
            ),
          ),
```

`_changeOrg`/`_changeDivision`/`orgCodes`/`divisions` 는 기존 그대로 사용 (변경 없음).

- [ ] **2-4. 통과 확인**: `flutter test test/rankings_screen_test.dart && flutter analyze` — 기존 테스트 전부 + 신규 2건 통과

- [ ] **2-5. 커밋**:

```
feat(app): 협회 랭킹의 협회 선택을 세그먼트에서 드롭다운으로 교체

협회가 계속 추가될 예정이라 세그먼트는 폭이 감당이 안 된다. 항목은
기존 SSOT(kRankingDivisions × OrgCatalog 라벨)를 그대로 써서 미러 협회
추가가 화면 수정 없이 반영된다. 부서 드롭다운과 한 줄 두 칸으로 배치하고,
협회 변경 시 부서 필드를 ValueKey 로 재생성해 stale value assert 를 막는다.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

---

## Task 3 — 내 기록 요약 카드 신설 + "내 기록 보기" 링크 제거 + 상태 슬롯 재배치

**Files**: `app/lib/screens/rankings/rankings_screen.dart`, `app/test/rankings_screen_test.dart`

**Interfaces**
- Consumes: Task 1 의 `api.playerRankings()`, `topDivisionRanking()`(providers.dart), 기존 `_NotMyDivisionNotice`/`RankingClaimPrompt`/`linkedOrgPlayerId`
- Produces: `MyRankingSummaryCard`(public, 테스트 대상), `_RankingScreenData.myRanking`, `_buildStatusSlot()`

### Steps

- [ ] **3-1. 실패 테스트 작성** — `rankings_screen_test.dart`.

`_FakeRankingApi` 에 협회 단위 내 순위 fixture 추가 (**필수**: `_load()` 가 새로 호출하므로 override 없으면 실제 네트워크를 탄다):

```dart
  // 생성자 파라미터에 추가:
  //   this.myRankings = const [],
  // 필드 추가:
  final List<OrgRankingRow> myRankings;

  @override
  Future<List<OrgRankingRow>> playerRankings({
    required String orgCode,
    required String orgPlayerId,
  }) async =>
      myRankings;
```

`_pumpScreen` 에도 `List<OrgRankingRow> myRankings = const []` 파라미터를 추가해 fake 에 전달한다.

테스트 그룹 추가:

```dart
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

    testWidgets('확정 연결이 없으면 카드 대신 기존 연결 유도가 그 자리에 뜬다', (tester) async {
      await _pumpScreen(tester, rows: rows, links: const [], myOrgs: const []);

      expect(find.byKey(const ValueKey('my-ranking-summary-card')), findsNothing);
      expect(find.textContaining('소속 협회·부서를 등록하면'), findsOneWidget);
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
```

`_FakeRankingApi` 생성자의 `myRankings` 파라미터, 테스트 파일 상단 `import 'package:go_router/go_router.dart';` 추가.

- [ ] **3-2. 실패 확인**: `flutter test test/rankings_screen_test.dart` → 카드 키 부재·링크 존재로 신규 4건 실패 확인

- [ ] **3-3. 구현 (1) — 데이터**: `_RankingScreenData` 에 필드 추가 (생성자에 `required this.myRanking` 포함):

```dart
  /// 지금 보는 **협회**에서의 내 대표 부서 순위(confirmed 연결 기준).
  /// 보는 부서와 내 부서가 달라도 채워진다 — 부서 조회(rows)와 별도로
  /// playerRankings 로 얻는다. 연결이 없거나, 연결은 있는데 공표 표에
  /// 행이 없으면(연초 리셋 등) null.
  final OrgRankingRow? myRanking;
```

`_load()` 의 링크 순회 직후(registeredHere 계산 앞)에 추가하고, 반환 객체에 `myRanking: topDivisionRanking(myRows)` 를 넣는다:

```dart
    // 내 기록 요약용 — 지금 보는 부서의 rows 에는 내 행이 없을 수 있어
    // (내 부서 ≠ 보는 부서) 협회+선수로 따로 조회한다. 대표 부서는 홈 등급
    // 카드와 같은 기준(topDivisionRanking, 협회 공표 순서 = 상위 부서 우선).
    var myRows = const <OrgRankingRow>[];
    if (linkedOrgPlayerId != null) {
      myRows = await api.playerRankings(
        orgCode: _orgCode,
        orgPlayerId: linkedOrgPlayerId,
      );
    }
```

- [ ] **3-4. 구현 (2) — 카드 위젯**: `rankings_screen.dart` 의 `// ── 본인 확인 카드` 섹션 앞에 추가:

```dart
// ── 내 기록 요약 카드 ─────────────────────────────────────────────────────

/// 드롭다운 바로 아래 "내 기록 요약". 지금 보는 협회에 confirmed 연결이
/// 있을 때만 뜨고, 협회를 바꾸면 그 협회 기준으로 바뀐다.
///
/// [ranking] 이 null 이어도 카드는 뜬다 — "내 기록 보기" 링크를 없앤 자리라
/// 이 카드가 /rankings/me 로 가는 유일한 진입점이다. 연결은 있는데 공표
/// 표에 행이 없는 경우(연초 협회 포인트 리셋 등)에 사라지면 기록 화면이
/// 고아가 된다.
class MyRankingSummaryCard extends StatelessWidget {
  const MyRankingSummaryCard({
    super.key,
    required this.orgCode,
    required this.ranking,
    required this.onTap,
  });

  final String orgCode;
  final OrgRankingRow? ranking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = ranking;
    // 내 랭킹 행과 같은 강조색(primaryContainer) — "내 것"의 색을 화면 안에서
    // 하나로 유지한다.
    return AppCard(
      key: const ValueKey('my-ranking-summary-card'),
      variant: AppCardVariant.outlined,
      backgroundColor: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tennisOrgShortLabel(orgCode)} 내 기록',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r == null
                      ? '공표된 순위 없음'
                      : '${divisionLabel(r.divisionCode)} ${r.rank}위 · '
                          '${NumberFormat('#,###').format(r.totalPoints)}P',
                  style: tt.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
        ],
      ),
    );
  }
}
```

(`intl` 의 `NumberFormat` 은 이 파일에 이미 import 돼 있다.)

- [ ] **3-5. 구현 (3) — 슬롯 추출·재배치**: `_RankingsScreenState` 에 메서드 추가. **기존 ListView 첫 자식의 if/else 체인을 조건·순서·주석 그대로 옮긴다** (우선순위는 codex 리뷰 2026-08-18 에 고정된 것 — 등록 0개 안내 > 후보 카드 > 확인 중 > 신청할 줄 없음 > 남의 부서 안내. 각 분기의 `data.linkedOrgPlayerId == null` 조건은 최상단 early-return 으로 대체된다):

```dart
  /// 드롭다운 아래 고정 슬롯. 이 협회에 confirmed 연결이 있으면 내 기록 요약
  /// 카드, 없으면 기존 연결 유도/후보 카드 체인이 같은 자리에 뜬다.
  ///
  /// 연결이 있으면 pending 이 남아 있어도 카드가 이긴다 — 연결이 끝난 사람에게
  /// '확인 중입니다'는 틀린 정보다(협회당 1명 1선수라 남은 pending 은 승인될 수
  /// 없는 잔재다).
  Widget _buildStatusSlot(_RankingScreenData data) {
    if (data.linkedOrgPlayerId != null) {
      return MyRankingSummaryCard(
        orgCode: _orgCode,
        ranking: data.myRanking,
        onTap: () => context.push('/rankings/me'),
      );
    }
    // ↓ 기존 ListView 체인 그대로 (주석 포함 이동).
    if (data.hasNoOrgRegistered) {
      return const _NotMyDivisionNotice(hasNoOrgRegistered: true);
    }
    if (data.candidate != null) {
      return RankingClaimPrompt(
        candidate: data.candidate!,
        onClaim: () => _claim(data.candidate!),
      );
    }
    if (data.hasPendingClaim) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('확인 중입니다', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    if (data.registeredHere &&
        data.claimableOrgPlayerIds.isEmpty &&
        data.disputableOrgPlayerIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          '이 표에서 신청할 수 있는 줄이 없습니다. '
          '가입할 때 넣은 이름이 협회 명단과 같아야 하고, '
          '이미 신청했거나 연결된 선수는 제외됩니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    if (!data.registeredHere) {
      return const _NotMyDivisionNotice(hasNoOrgRegistered: false);
    }
    return const SizedBox.shrink();
  }
```

`build()` 변경:
1. 드롭다운 Row 바로 다음, "내 기록 보기" `TextButton.icon` Padding 블록을 **삭제**하고 그 자리에 슬롯을 넣는다:

```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              0,
            ),
            child: FutureBuilder<_RankingScreenData>(
              future: _future,
              builder: (context, snap) {
                final data = snap.data;
                // 로드 전·실패 시 빈 슬롯 — 로딩 표시는 목록 영역이 담당한다.
                if (data == null) return const SizedBox.shrink();
                return _buildStatusSlot(data);
              },
            ),
          ),
```

2. ListView `children` 에서 기존 안내 체인(`if (data.hasNoOrgRegistered && ...)` 부터 `_NotMyDivisionNotice(hasNoOrgRegistered: false),` 까지)을 **통째로 삭제**한다. 남는 것: `visibleRows.isEmpty` 분기와 테이블(`_RankingTableHeader` + `RankingList`).

- [ ] **3-6. 통과 확인**: `flutter test test/rankings_screen_test.dart && flutter analyze`
  - 신규 4건 통과.
  - 기존 '등록 안 한 부서 안내' 그룹 5건은 `textContaining` 기반이라 슬롯 이동 후에도 통과해야 한다. '확정 연결이 있으면 행 버튼도 후보 카드도 안 뜬다' 테스트는 이제 요약 카드가 뜨지만 `find.text('본인')`/`find.text('신청')` 은 여전히 `findsNothing` 이므로 통과 (카드 문구에 '신청'·'본인' 리터럴을 넣지 않은 이유).
  - unused 확인: 링크 제거 후에도 `go_router` import 는 카드 onTap·`_NotMyDivisionNotice` 가 쓰므로 유지. `Icons.query_stats_rounded` 만 사라진다.

- [ ] **3-7. 전체 테스트**: `flutter test` (전 스위트 — providers/홈 등급 카드 회귀 확인)

- [ ] **3-8. 커밋**:

```
feat(app): 랭킹 화면에 내 기록 요약 카드 신설, "내 기록 보기" 링크 제거

드롭다운 바로 아래 고정 슬롯에, 지금 보는 협회 기준 내 순위·부서·누적
포인트를 요약해 보여준다(협회를 바꾸면 그 협회 기준으로 바뀜). 탭하면
기존 /rankings/me 로 간다 — 화면은 그대로 두고 진입점만 카드로 바꿨다.
confirmed 연결이 없으면 같은 자리에 기존 연결 유도/후보 카드 체인이
우선순위 그대로 뜬다(ListView 에서 슬롯으로 이동).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

---

## Self-Review 체크리스트

- [ ] `flutter analyze` 경고 0건 (CI 는 warning 도 에러 — unused import/변수/필드 없음)
- [ ] `flutter test` 전 스위트 통과 (특히 `rankings_screen_test.dart` 기존 테스트 전부 무수정 통과 — 수정한 것은 `_FakeRankingApi`/`_pumpScreen` 확장뿐인지)
- [ ] `dynamic` 신규 도입 없음 (`Map<String, dynamic>` 은 기존 Supabase row 관례만)
- [ ] `myCurrentRankings()` 의 정렬(`division_code` 내림차순)이 리팩터 전과 동일한지 — `myRankingHistoryProvider`·`my_record_screen` 동작 불변
- [ ] 협회 드롭다운 항목이 `kRankingDivisions.keys` × `tennisOrgShortLabel` 에서만 나오는지 (화면에 'gj'/'jn' 리터럴 신규 하드코딩 없음)
- [ ] 협회 전환 시 부서 드롭다운이 새 협회 첫 부서로 리셋되고 assert 크래시가 없는지 (2-1 테스트가 커버)
- [ ] 슬롯 분기 우선순위가 기존 ListView 체인과 동일한지 (등록 0개 > 후보 > 확인 중 > 신청 줄 없음 > 남의 부서) + 이동한 주석 보존
- [ ] confirmed 연결 + 잔여 pending 케이스에서 카드가 이기는 동작 변경이 커밋 메시지/주석에 설명돼 있는지
- [ ] 서버/DB/Edge Function 변경이 하나도 없는지 (마이그레이션 폴더 diff 없음)
- [ ] 320px·200% 글자 크기에서 카드/드롭다운 Row 가 overflow 나지 않는지 수동 확인 (`isExpanded: true`, `FittedBox` 불필요 여부)

### Critical Files for Implementation

- /Users/ssfak/Documents/01-github/AllRound/app/lib/screens/rankings/rankings_screen.dart
- /Users/ssfak/Documents/01-github/AllRound/app/lib/services/ranking_api.dart
- /Users/ssfak/Documents/01-github/AllRound/app/test/rankings_screen_test.dart
- /Users/ssfak/Documents/01-github/AllRound/app/lib/utils/grade_labels.dart (SSOT 참조만, 무수정)
- /Users/ssfak/Documents/01-github/AllRound/app/lib/state/providers.dart (`topDivisionRanking` 재사용, 무수정)