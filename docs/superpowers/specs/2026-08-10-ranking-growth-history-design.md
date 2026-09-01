# 랭킹 성장 기록 (2단계) — 순위 추이 · 시즌 기록 · 선수 상세

- 작성일: 2026-08-10
- 선행: `2026-08-03-personal-record-history-design.md` (개인 기록장 1단계 — 이 문서의 §7.2 "2단계"를 구현), `2026-08-03-org-ranking-mirror-design.md`
- 상태: kimabba 승인 완료(대화 중), 구현 계획 대기

---

## 1. 목적

1단계(개인 이력 타임라인)는 이미 나갔다. 이번엔 그 문서가 "스냅샷이 쌓인 뒤"로 미뤄둔 **순위 추이 그래프**를 켜고, 여기에 리텐션 훅으로 **"이 시즌 기록" 통계**(참가 횟수·우승 횟수·베스트 순위·전적 분포)를 더한다.

Commander 표현: "테니스 랭킹이나 대회 이력, 올해 참가횟수 등등 재미있는 기록들을 추가하고 싶어 — 그래야지 기록하지 않을까".

## 2. 선행 설계와 달라지는 점 (명시적 결정)

1단계 문서(§7, §8)와 비교해 이번에 뒤집은 결정 두 가지 — 우연한 스코프 확장이 아니라 이 대화에서 명시적으로 승인됐다.

| # | 1단계 문서 | 이번 결정 |
|---|---|---|
| 1 | §8 "범위 밖: 다른 사람 전적 조회·비교" | **연다.** 랭킹 표에서 아무 선수나 눌러도 같은 기록을 본다(`org_player_results_read`/`org_ranking_snapshots_read` RLS, `auth.role() = 'authenticated'` — `org_rankings` 공개 수준과 통일) |
| 2 | §7 진입점 = "프로필(MY)의 내 대회 기록 섹션" | **MY에서 완전히 뗀다.** MY는 프로필·설정 전용으로 남기고, 진입점은 **랭킹 탭 안의 버튼/카드**로 옮긴다 |

이유(#1): 랭킹 표 자체가 이미 이름·소속·점수를 로그인 사용자 전체에 공개한다(`org_rankings_read`). 같은 협회 공표 데이터인 개인 전적·순위 이력만 막을 근거가 약하다.

이유(#2): "마이는 설정 관련 내용들만" — 기록·통계는 설정이 아니라 콘텐츠이므로, 성격이 같은 대회/랭킹 영역에 두는 게 IA상 맞다.

## 3. 데이터

### 3.1 이미 있는 것 (그대로 씀)

- `org_rankings` — 현재 순위·포인트 (RLS: 로그인 전체 공개, 기존)
- `org_player_results` — 대회별 전적(대회명·날짜·성적·포인트) (RLS: `org_player_results_read`, 오늘 이미 열어둠)
- `org_ranking_snapshots` — 부서 내 순위·포인트의 일별 스냅샷. **2026-08-04부터 자동 적재 중**, 오늘 기준 6일치(21,264행). RLS는 아직 `own_select`(본인 연결자만)만 있음 — 이번에 연다.

### 3.2 신규

**마이그레이션**: `org_ranking_snapshots_read` 정책 추가 — `org_player_results_read`와 동일 패턴(`for select to authenticated using (true)`). 기존 `org_ranking_snapshots_own_select`/`_admin_all`은 그대로 둔다(OR로 합쳐지므로 안전).

**신규 모델** `OrgRankingSnapshot` (`app/lib/models/org_ranking_snapshot.dart`): `orgCode`, `divisionCode`, `orgPlayerId`, `capturedOn`, `rank`, `totalPoints`.

**신규 API** (`ranking_api.dart`):
```dart
Future<List<OrgRankingSnapshot>> playerRankingHistory({
  required String orgCode,
  required String divisionCode,
  required String orgPlayerId,
}) // captured_on 오름차순, 전체 기간 반환(현재 규모에서 페이지네이션 불필요 — 연 ~365행/부서당 선수)
```

**"이 시즌 기록" 통계**는 새 테이블·RPC 없이, 이미 받아온 `List<PlayerResult>`(org_player_results, 클라이언트가 이미 fetch)에서 계산한다:
- **올해 참가 대회 수**: `results.where((r) => r.playedOn.year == 올해).length`
- **누적 우승 횟수**: `results.where((r) => r.resultRound == 1).length` (연도 제한 없음 — "누적")
- **시즌 최고 랭킹**: `playerRankingHistory()` 결과 중 `rank`가 가장 작은(=1등에 가까운) 값. 스냅샷 이력 자체가 2026-08-04부터라 사실상 "지금 시즌" 범위
- **전적 분포**: `results`를 `resultRound`로 그룹핑해 카운트(1=우승, 2=준우승, 4=4강 …). `resultRound == null`(정규화 실패, 원문만 있는 행)은 "기타 N"으로 묶는다

전부 이미 로드된 리스트에서 계산하는 순수 함수라 새 네트워크 호출이 없다.

## 4. 화면

### 4.1 MY 화면

`MyRecordSection`(`widgets/profile/my_record_widgets.dart`)과 `profile_screen.dart`에서의 호출부를 **삭제**한다. MY는 프로필 카드 + "MY 바로가기"(프로필 수정·관심 대회·내 클럽·룰북) + 설정만 남는다.

### 4.2 랭킹 탭 — 새 진입점

`rankings_screen.dart`의 필터 영역(부서 드롭다운 아래, 검색창 위 또는 그 근처)에 카드/버튼 하나:
- 미연결: "내 기록 보기" 대신 연결 유도 문구 + `RankingClaimPrompt`로 스크롤 이동, 또는 바로 `RecordSection`을 push해 그 안에서 `ConnectPrompt` 노출(§4.3과 동일 컴포넌트 재사용이 더 간단 — 후자로 확정)
- 연결됨: "내 기록 보기" 버튼 → `context.push('/rankings/me')`로 전체화면 push

새 라우트 `/rankings/me` (router.dart, `ShellRoute` 밖 — 탭 아님, 뒤로가기로 돌아옴): `MyRecordScreen`이 `RecordContent`를 `Scaffold`+`AppBar`로 감싸 표시.

### 4.3 선수 상세시트 (오늘 만든 `player_detail_sheet.dart`)

같은 통계·그래프 블록을 그대로 추가. 미연결(전적 없음)인 선수는 "이 시즌 기록" 블록 자체를 스킵(0/0/–/없음을 나열하지 않는다 — 데이터 없음과 "0회"는 다른 사실이다).

### 4.4 `RecordContent` 확장 (공용 컴포넌트, 두 곳에서 재사용)

기존 구조(현재 순위 → 최고의 순간 → 전적 리스트)에 두 블록을 끼워 넣는다:

```
현재 순위 (기존)
├─ 이 시즌 기록  ← 신규: 참가 N · 우승 N · 시즌 최고 M위 · 전적 분포
├─ 순위 추이     ← 신규: 스파크라인 (스냅샷 2건 미만이면 "추이를 보려면 며칠 더 필요해요")
최고의 순간 (기존)
전적 리스트 (기존)
```

`results`/`rankings`에 더해 새 파라미터 `snapshots: List<OrgRankingSnapshot>`를 받는다. 두 호출부(`MyRecordScreen`, `player_detail_sheet.dart`) 모두 `playerRankingHistory()`를 각자 fetch해 넘긴다.

### 4.5 순위 추이 스파크라인

새 위젯 `widgets/rankings/rank_trend_sparkline.dart`. 외부 차트 라이브러리 없이 `CustomPainter`로 직접 그린다(데이터가 스냅샷당 최대 수백 점 규모라 충분).

- X축: `capturedOn`, Y축: `rank` — **낮을수록 위**(1등이 그래프 위쪽)로 반전
- 점 2개 미만이면 그래프 대신 안내 문구
- 색·접근성은 구현 단계에서 `dataviz` 스킬 가이드를 따른다(현재 프로젝트 팔레트 재사용, 새 색 발명 안 함)

## 5. 표기 규칙 (1단계와 동일 원칙 유지)

- "협회 공표 기준" 출처 문구는 기존 `RankingSourceNotice`가 이미 담당 — 새 블록도 그 아래에 위치해 같은 출처 고지를 공유한다
- 앱이 만든 점수가 아님을 반복해서 강조하지 않는다(이미 상위에 고지됨) — 통계 블록 라벨은 "이 시즌 기록"처럼 사실 서술형으로, "레벨"·"등급" 같은 자체 용어를 쓰지 않는다(1단계 결정 3과 동일 원칙: 자체 점수·레벨 체계를 만들지 않는다)

## 6. 범위 밖 (이번에도 안 만든다)

- 승급 네비게이터("다음 등급까지 X") — JY-119 v2, 협회 승급 규정 협의 필요
- 올라운드 자체 AP/레벨 게이지 — 1단계 결정 3 유지
- 다른 사람과의 비교/랭킹 대결 UI — 조회는 열지만 "비교"는 별개 기능
- 순위 변동 푸시 알림
- `match_entries`/소모임 이력 — 1단계 결정 1 유지(원천은 협회 랭킹만)

## 7. 테스트

| 대상 | 방법 |
|---|---|
| 통계 계산 함수(참가 수/우승 수/베스트 랭킹/전적 분포) | 순수 함수 단위 테스트 — 빈 리스트, `resultRound null` 섞인 리스트, 연도 경계(12/31↔1/1) 케이스 |
| 스파크라인 | 위젯 테스트 — 점 0/1개일 때 안내 문구, 2개 이상일 때 그려지는지(`tester.takeException()` 없음 확인 수준, 픽셀 검증은 안 함) |
| RLS | 오늘 `org_player_results_read`에 준하는 정책 — 다른 사용자 스냅샷이 조회되는지 직접 쿼리로 확인 |
| MY 화면 회귀 | 기존 `my_record_section_test.dart` 삭제 대상 케이스 정리, `profile_screen` 관련 테스트에서 "내 기록" 섹션 부재 확인 |
| 라우팅 | `/rankings/me` 새 라우트 — 미연결 시 유도 카드, 연결 시 기록 화면 |

## 8. 미해결

1. `/rankings/me` 라우트가 셸(하단 네비) 밖 화면이라 뒤로가기 동작을 실기기에서 확인 필요(`AppBackButton` 패턴 재사용 여부는 구현 단계에서 확인)
2. 선수 상세시트에서 스냅샷을 매번 새로 fetch하면 같은 선수를 반복해서 열 때마다 쿼리가 나간다 — 캐싱은 이번 스코프에서 안 함(트래픽 낮음, 나중에 필요하면 추가)
3. 스냅샷 시작일(2026-08-04) 이전 구간은 1단계 문서 §10-4와 동일하게 그래프에 없음 — 역산 안 함
