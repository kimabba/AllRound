# 협회 랭킹 리스트 — 클럽 멤버 리스트 톤앤매너 통일 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 협회 랭킹 리스트 행(`_RankingRow`)을 클럽 멤버 리스트(`club_detail_screen.dart`)와 같은 톤앤매너로 맞춘다 — 행마다 카드, 아바타(이니셜), 이름 폰트 굵기 w800. 아바타 추가는 "탭하면 개인 이력이 보인다"는 기존 동작(`openPlayerDetailSheet`, 이미 구현됨)에 눈에 보이는 탭 대상을 만들어준다.

**Architecture:** `RankingList`이 감싸던 단일 `AppCard`+`Divider` 구조를, 클럽 멤버 리스트처럼 행마다 `AppCard`를 감싸고 행 사이에 `SizedBox` 간격을 두는 구조로 바꾼다. 랭킹표 데이터(`OrgRankingRow`)에는 실제 프로필 사진 필드가 없으므로(협회 크롤 데이터, 앱 계정과 무관) 클럽 멤버 리스트의 "사진 없으면 이니셜" 폴백과 같은 방식으로 이니셜 아바타를 쓴다.

**Tech Stack:** Flutter/Dart. 백엔드·API 변경 없음.

## Global Constraints

- 탭 시 열리는 화면(`openPlayerDetailSheet` → `_PlayerDetailSheet` → `RecordContent`)은 이미 정상 동작한다 — 이번 작업은 시각적 통일과 탭 대상 가시성만 다룬다.
- `OrgRankingRow`(app/lib/models/org_ranking.dart)에 아바타 URL 필드가 없다 — 새 필드를 추가하지 않는다(협회 크롤 데이터에 실제 사진이 없다). 이니셜 아바타로 대체한다.
- 기존 위젯 테스트(`ranking-row-mine` 키, 이름 텍스트 렌더링)가 계속 통과해야 한다.
- CI가 warning도 에러로 처리한다 — 안 쓰는 변수/import를 남기지 않는다.

---

## File Structure

- **Modify:** `app/lib/screens/rankings/rankings_screen.dart` — `RankingList`(간격 로직), `_RankingRow`(행별 AppCard + 아바타 + 폰트 굵기), 화면 레벨 이중 카드 래핑 제거(889~899행).
- **Modify:** `app/test/rankings_screen_test.dart` — 아바타 렌더링 테스트 추가, 기존 테스트는 그대로 유지되는지 확인.

---

### Task 1: `_RankingRow` — 행별 카드 + 아바타 + 폰트 굵기

**Files:**
- Modify: `app/lib/screens/rankings/rankings_screen.dart:137-271`
- Test: `app/test/rankings_screen_test.dart`

> **⚠️ 2026-08-25 main 최신화 보정:** PR #476이 이 화면을 바꿨다 — `_RankingRow` 가 `onTap` 파라미터를 받고(`RankingList.onPlayerTap` 콜백에서 내려옴, 탭 동작은 화면의 `_openPlayerHistory` 가 담당), 리스트 위에 컬럼 라벨 헤더 `_RankingTableHeader`(283행 부근)가 추가됐다. **`onTap`/`onPlayerTap` 구조를 그대로 유지할 것** — `_RankingRow` 안에서 `openPlayerDetailSheet` 를 직접 부르지 않는다. 구현자는 반드시 현재 파일을 먼저 읽고 라인 번호를 재확인할 것.

**Interfaces:**
- Consumes: 기존 `OrgRankingRow`, `AppCard`/`AppCardVariant`(`../../widgets/app_card.dart`) — 이미 이 파일이 import 중. 탭 동작은 기존 `onTap` 파라미터(#476) 그대로.
- Produces: `_RankingRow`, `RankingList`의 외부 시그니처(생성자 파라미터)는 불변 — 화면 어디서 호출해도 코드 변경 없이 그대로 동작한다.

- [ ] **Step 1: 실패하는 테스트 작성 — 행마다 아바타가 보여야 한다**

`app/test/rankings_screen_test.dart` 의 `'내 계정과 연결된 행은 강조된다'` 테스트 바로 뒤에 추가한다(#476으로 파일에 테스트가 늘었으니 라인 번호가 아니라 **테스트 이름으로 위치를 찾을 것**).

```dart
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `cd app && flutter test test/rankings_screen_test.dart`
Expected: FAIL — `find.byType(CircleAvatar)` 가 0개를 찾는다(`findsNWidgets(2)` 불일치).

- [ ] **Step 3: `_RankingRow` 를 행별 `AppCard` + 아바타 + w800 폰트로 교체**

`app/lib/screens/rankings/rankings_screen.dart` 188~277행 부근의 기존 `_RankingRow` 클래스 전체를 아래로 교체한다. **기존 `onTap` 파라미터를 그대로 유지한다(#476)** — 탭 핸들러는 화면에서 `onPlayerTap` 으로 내려온다.

```dart
class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.row,
    required this.isMine,
    this.onClaim,
    this.onDispute,
    this.onTap,
  });

  final OrgRankingRow row;
  final bool isMine;
  final VoidCallback? onClaim;
  final VoidCallback? onDispute;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 랭킹표는 협회 크롤 데이터라 프로필 사진이 없다 — 클럽 멤버 리스트와 같은
    // 이니셜 폴백을 쓴다(app/lib/screens/clubs/club_detail_screen.dart 의
    // CircleAvatar 패턴과 동일).
    final initial =
        row.playerName.characters.isEmpty ? '?' : row.playerName.characters.first;
    return AppCard(
      key: isMine ? const ValueKey('ranking-row-mine') : null,
      variant: AppCardVariant.outlined,
      backgroundColor: isMine ? cs.primaryContainer : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
              width: 32, child: Text('${row.rank}', style: tt.bodyLarge)),
          const SizedBox(width: AppSpacing.sm),
          CircleAvatar(
            // 내 행은 카드 배경 자체가 primaryContainer 라, 아바타도 같은 색이면
            // 원이 배경에 묻혀 안 보인다 — 내 행일 때는 surface 로 대비를 준다.
            backgroundColor: isMine ? cs.surface : cs.primaryContainer,
            child: Text(
              initial,
              style: TextStyle(
                color: isMine ? cs.primary : cs.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.playerName,
                  style:
                      tt.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (row.clubRaw != null && row.clubRaw!.isNotEmpty)
                  Text(
                    row.clubRaw!,
                    style:
                        tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text('${row.totalPoints}', style: tt.bodyLarge),
          if (onClaim != null) ...[
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              // 테마 기본 minimumSize 가 Size.fromHeight(폭 무한)라 Row 안에서는
              // 명시로 덮어써야 한다(theme-infinite-width-button-landmine).
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppSizes.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              onPressed: onClaim,
              child: const Text('본인'),
            ),
          ],
          // 신청 버튼이 사라지는 자리(이미 남과 연결된 줄)에 대신 붙는다.
          // 둘이 같이 뜨는 경우는 없다 — 두 집합이 배타적이다.
          if (onDispute != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizes.control),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
              ),
              onPressed: onDispute,
              child: const Text('이의신청'),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `RankingList` 의 `Divider` 구분선을 행별 카드 간격(`SizedBox`)으로 교체**

같은 파일 137~186행 부근의 기존 `RankingList` 클래스 `build()` 메서드를 아래로 교체한다(클래스 선언부·필드·생성자는 그대로 두고 `build()` 본문만 바꾼다). **`onPlayerTap` → `onTap` 연결(#476)은 그대로 유지한다.**

```dart
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _RankingRow(
            row: rows[i],
            isMine: rows[i].orgPlayerId != null &&
                rows[i].orgPlayerId == linkedOrgPlayerId,
            onTap: rows[i].orgPlayerId == null || onPlayerTap == null
                ? null
                : () => onPlayerTap!(rows[i]),
            onClaim: onClaim != null &&
                    rows[i].orgPlayerId != null &&
                    claimableOrgPlayerIds.contains(rows[i].orgPlayerId)
                ? () => onClaim!(rows[i])
                : null,
            onDispute: onDispute != null &&
                    rows[i].orgPlayerId != null &&
                    disputableOrgPlayerIds.contains(rows[i].orgPlayerId)
                ? () => onDispute!(rows[i])
                : null,
          ),
        ],
      ],
    );
  }
```

`cs` 지역변수(옛 `Divider(color: cs.outlineVariant)` 용)는 더 안 쓰므로 제거한다 — 남기면 `flutter analyze` 의 unused_local_variable 경고가 CI를 깬다(START-HERE.md §5 규칙5).

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd app && flutter test test/rankings_screen_test.dart`
Expected: PASS — Step 1에서 추가한 아바타 테스트 포함, 기존 `'순위표 행이 렌더링된다'`·`'내 계정과 연결된 행은 강조된다'` 테스트도 그대로 통과(텍스트·`ValueKey('ranking-row-mine')` 는 위치만 `AppCard` 로 옮겨졌을 뿐 그대로 존재).

- [ ] **Step 6: 커밋**

```bash
git add app/lib/screens/rankings/rankings_screen.dart app/test/rankings_screen_test.dart
git commit -m "feat(app): 협회 랭킹 행을 클럽 멤버 리스트 톤앤매너로 통일 (행별 카드 + 아바타)"
```

---

### Task 2: 화면 레벨 이중 카드 래핑 제거 + 테이블 헤더 정렬 보정

**Files:**
- Modify: `app/lib/screens/rankings/rankings_screen.dart:943-959` (화면 래핑부), `:280-308` 부근 (`_RankingTableHeader`)

**Interfaces:** 없음 — 순수 레이아웃 정리.

행마다 이미 `AppCard`로 감싸이므로, 화면이 헤더+리스트 전체를 또 한 번 `AppCard`로 감싸면 카드 안에 카드가 겹쳐 보인다(이중 테두리). 클럽 멤버 리스트도 리스트 전체를 카드로 감싸지 않고 각 항목만 카드다 — 같은 패턴으로 맞춘다. 컬럼 라벨 헤더(`_RankingTableHeader`, #476 추가)는 "누적 포인트"가 뭘 뜻하는지 알려주는 정보라 **지우지 않고 유지**하되, 행에 아바타가 들어가면서 이름 컬럼 시작 위치가 밀리므로 헤더 정렬만 보정한다.

- [ ] **Step 1: 이중 래핑 제거 (헤더는 카드 밖으로 유지)**

`app/lib/screens/rankings/rankings_screen.dart` 943~959행의 기존 코드:

```dart
                    else
                      AppCard(
                        variant: AppCardVariant.outlined,
                        child: Column(
                          children: [
                            const _RankingTableHeader(),
                            RankingList(
                              rows: visibleRows,
                              linkedOrgPlayerId: data.linkedOrgPlayerId,
                              claimableOrgPlayerIds: data.claimableOrgPlayerIds,
                              disputableOrgPlayerIds: data.disputableOrgPlayerIds,
                              onClaim: _claim,
                              onDispute: _dispute,
                              onPlayerTap: _openPlayerHistory,
                            ),
                          ],
                        ),
                      ),
```

를 아래로 교체한다(바깥 `AppCard` 만 벗긴다):

```dart
                    else
                      Column(
                        children: [
                          const _RankingTableHeader(),
                          RankingList(
                            rows: visibleRows,
                            linkedOrgPlayerId: data.linkedOrgPlayerId,
                            claimableOrgPlayerIds: data.claimableOrgPlayerIds,
                            disputableOrgPlayerIds: data.disputableOrgPlayerIds,
                            onClaim: _claim,
                            onDispute: _dispute,
                            onPlayerTap: _openPlayerHistory,
                          ),
                        ],
                      ),
```

- [ ] **Step 1-b: `_RankingTableHeader` 정렬 보정**

행 레이아웃이 `순위(32) + 간격(sm=8) + 아바타(40) + 간격(md=12) + 이름...` 으로 바뀌므로, 헤더의 '선수 · 소속' 라벨 시작 위치를 맞춘다. `_RankingTableHeader` 의 `build()` 안 `Row` children 을 아래로 교체한다(기존: `SizedBox(width: 36...)` + `SizedBox(width: AppSpacing.md)` + `Expanded` + `Text` + `SizedBox(width: 24)`).

```dart
        children: [
          SizedBox(width: 32, child: Text('순위', style: style)),
          const SizedBox(width: AppSpacing.sm),
          // 행의 아바타(지름 40) + 이름 앞 간격(md)과 정렬을 맞춘다.
          const SizedBox(width: 40 + AppSpacing.md),
          Expanded(child: Text('선수 · 소속', style: style)),
          Text('누적 포인트', style: style),
        ],
```

행이 개별 카드(`horizontal: AppSpacing.md` 내부 패딩)가 되면서 헤더도 같은 좌우 기준을 갖도록, `_RankingTableHeader` 의 바깥 `Padding` 은 `EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs)` 그대로 둔다(이미 md라 맞음).

- [ ] **Step 2: 전체 랭킹 화면 테스트 통과 확인 (스크린 통합 테스트 포함)**

Run: `cd app && flutter test test/rankings_screen_test.dart test/ranking_claims_test.dart`
Expected: PASS. `_pumpScreen` 으로 `RankingsScreen` 전체를 렌더링하는 테스트들이 여기 포함돼 있어, 이중 래핑 제거로 레이아웃이 깨지지 않는지(오버플로 등) 같이 검증된다.

- [ ] **Step 3: `flutter analyze` 로 안 쓰는 import 등 확인**

Run: `cd app && flutter analyze`
Expected: No issues found. (`AppCard`/`AppCardVariant` import 는 `_RankingRow` 가 여전히 쓰므로 unused import 경고는 나지 않아야 한다.)

- [ ] **Step 4: 커밋**

```bash
git add app/lib/screens/rankings/rankings_screen.dart
git commit -m "fix(app): 랭킹 리스트 이중 카드 래핑 제거 (행별 카드로 대체됨)"
```

---

## Self-Review 체크리스트 (계획 작성자가 실행, 참고용)

- 톤앤매너 조사에서 나온 4개 불일치(아바타 없음/행별 카드 없음/폰트 굵기 w700/패딩 책임 레이어) 전부 Task 1~2에서 다룸. 바텀시트 모서리 차이는 재확인 결과 `app_theme.dart` 의 전역 `bottomSheetTheme.shape` 가 이미 `AppRadius.sheet` 라 실제로는 차이가 없었다(오탐) — 별도 작업 불필요.
- "사진 클릭 → 이력" 요청은 이니셜 아바타 추가로 탭 대상이 시각적으로 드러나는 것으로 충족한다. 실제 탭 핸들러(`openPlayerDetailSheet`)는 이미 존재하며 변경하지 않는다.
- placeholder 없음 — 모든 스텝에 실제 코드/명령 포함.

## Fable 모델 검토 반영 이력 (2026-08-25)

독립 리뷰(claude-fable-5)에서 나온 지적을 반영했다: `isMine` 일 때 카드 배경(`cs.primaryContainer`)과 아바타 배경(`cs.primaryContainer`)이 같은 색이라 원이 배경에 묻혀 안 보였을 것 — 내 행일 때만 아바타를 `cs.surface`/`cs.primary` 로 대비를 주도록 Task 1 Step 3 수정. 그 외 라인 번호·`AppCard` API·`.characters` import 관례는 전부 실제 코드와 일치한다고 확인됨.
