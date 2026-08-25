# 개인 이력 크롤 — 연결자 한정 → 전 선수 확장 (변경분만) — 작업 지시

- 작성일: 2026-08-20
- 선행: `2026-08-03-org-ranking-mirror-design.md`, `2026-08-03-personal-record-history-design.md`
- 관련 PR: #468 (`fix/org-player-history-dedupe-conflict` — 단체전 중복 행 upsert 롤백 버그 수정, 이 작업 시작 전 main에 머지되어 있어야 함)
- 상태: kimabba 승인 완료("1. 그렇게 하자 2. 일단 하자") — 구현 대기
- 이 문서는 **다음 세션에 그대로 넘길 작업 지시**다. 조사는 끝났고 결정도 났다 — 설계 자체를 다시 논의하지 말고 구현으로 바로 들어갈 것.

---

## 1. 배경 (이미 조사·확인된 사실)

랭킹 화면에서 선수를 탭하면 `player_detail_sheet.dart` → `ranking_api.dart#playerResults()` → `org_player_results` 테이블에서 개인 대회 이력을 보여준다. 그런데 지금은 **`org_player_links.status='confirmed'`로 본인 연결한 선수만** 이 개인 이력이 크롤돼 있다(`gnuboard_player_history.ts#crawlPlayerHistories`). 연결 안 한 나머지는 랭킹표엔 나오지만 탭하면 "아직 협회에 등록된 전적이 없습니다"만 뜬다.

이걸 **연결 여부와 무관하게 랭킹표에 있는 전 선수로 확장**하기로 kimabba 승인 받음. 단, 매일 전원(현재 3,546명)을 무작정 재크롤하면 안 된다 — 아래 실측 근거.

### 실측 근거 (2026-08-20, Supabase MCP로 직접 확인)

- `org_rankings` 전체 랭커: 광주(gj) 1,709명 + 전남(jn) 1,837명 = **3,546명**
- `org_ranking_snapshots` 테이블이 **랭킹표에 있는 전 선수의 (org_code, division_code, org_player_id, captured_on, rank, total_points)를 이미 매일 무료로 적재 중** — `replace_org_ranking_division` RPC 안에서 랭킹 부서 교체 직후 같은 트랜잭션으로 insert됨(마이그레이션 `20260804010000_personal_record_history.sql` §3). 연결 여부와 무관하게 전원 대상.
- jn 1,837명 기준 **최근 4일(2026-08-15~08-19)간 `total_points`가 바뀐 선수 = 0명**. 즉 랭킹 포인트는 협회가 대회 결과를 집계·발표할 때만 움직이고 평상시엔 거의 안 바뀐다 → "어제 대비 바뀐 선수만" 크롤하면 평상시 추가 요청은 거의 0건에 가깝다.
- 반례: **최초 실행(백필)은 예외다.** 기존 데이터가 없으니 전원이 "신규"로 잡혀 한 번에 3,546건을 시도하게 된다 — 이건 별도로 다뤄야 한다(§3.3).
- `crawl_audit`에서 확인한 실제 소요시간: gj 6개 부서 랭킹 교체 + 소수 연결자 이력 크롤 전체가 **~3초**(`2026-08-19 21:00:09.393` → `21:00:12.316`). Edge Function 타임아웃 예산을 감안하면 회당 크롤 가능한 "개인 이력 대상" 인원에 현실적인 상한이 있다 — 정확한 상한은 Supabase 프로젝트 플랜의 edge function 타임아웃 값을 확인해서 보수적으로 잡을 것(예: 100명/회부터 시작해 `crawl_audit`의 `started_at`~`finished_at` 실측으로 튜닝).

---

## 2. 확정된 결정

| # | 결정 | 근거 |
|---|---|---|
| 1 | 개인 이력 크롤 대상을 "confirmed 연결자"에서 **"변경분(포인트가 바뀐 선수) + 신규 랭커 + confirmed 연결자(항상 포함)"**로 확장한다 | kimabba 승인. 연결자는 "내 기록" 화면이 직접 의존하므로 무조건 최신이어야 함 — 변경분 로직이 이들을 놓치는 일이 없게 별도로 always-include 유지 |
| 2 | 변경 판정은 **"마지막으로 개인 이력을 성공적으로 크롤했을 때의 포인트" vs "현재 org_rankings.total_points"** 비교로 한다. 어제-오늘 스냅샷 diff가 아니다 | 며칠 건너뛰어도(회차 상한에 걸려 못 돈 선수) 추적이 끊기지 않게. 아래 §3.1 |
| 3 | 회차당 크롤 인원에 **상한을 둔다.** 상한을 넘는 후보는 이번 회차에 안 돌고 다음 회차로 자연히 넘어간다(위 §2 판정 기준이 상태 기반이라 별도 큐 테이블 없이도 이월됨) | Edge Function 타임아웃 + 협회 사이트 부하 방지 |
| 4 | **최초 백필(3,546명)은 일간 크론과 분리한 별도 1회성 작업**으로 다룬다. 일간 크론의 상한을 그대로 쓰면 백필에 수십 회차(수십 일)가 걸려 기능이 하염없이 안 채워짐 | §3.3 |
| 5 | 요청 사이에 최소한의 간격(예: 100~200ms)을 둔다 | 지금은 없음(`for` 루프 안에서 딜레이 없이 순차 `fetch`) — 요청량이 확 늘어나므로 협회 사이트에 대한 예의 차원 |
| 6 | 개인정보/협회 동의 범위 재검토는 **이 작업 지시에 포함하지 않는다** — kimabba가 "일단 하자"로 결론 냄. 다만 나중에 문제되면 되돌릴 수 있게 이 결정과 배경을 PR 설명에 남길 것 | kimabba 판단, 문서화만 요구 |

---

## 3. 구현 설계

### 3.1 변경 판정용 상태 테이블 (신규)

기존 `org_ranking_snapshots`(일자별 스냅샷)를 어제-오늘로 diff하는 방식은 회차를 건너뛰면 추적이 끊긴다. 대신 "마지막으로 개인 이력 크롤을 시도(성공)했을 때의 포인트"를 별도로 기록하는 얇은 상태 테이블을 추가한다.

```sql
create table public.org_player_history_crawl_state (
  org_code        text not null,
  org_player_id   text not null,
  last_points     int not null,
  last_crawled_at timestamptz not null default now(),
  primary key (org_code, org_player_id)
);
```

- 크롤러(service_role) 전용 — 클라이언트 RLS/grant 불필요(기존 크롤러 전용 테이블 관례를 따를 것, 예: `replace_org_ranking_division`처럼 anon/authenticated에 select 조차 안 열 것. 필요 여부는 구현하며 확인).
- `crawlPlayerHistories` 안에서 개인 이력 upsert가 **성공**한 직후 `(org_code, org_player_id, last_points=<그 시점 org_rankings.total_points>, last_crawled_at=now())`를 upsert. 실패한 선수는 갱신하지 않는다 — 다음 회차에 다시 후보로 잡히게 하기 위함(현재 `crawlPlayerHistories`가 실패를 `failures`로 모으는 기존 패턴과 동일한 철학).

### 3.2 후보 선정 쿼리

일간 랭킹 크롤(`gnuboardRankingParser`, 부서 6개 교체 끝난 뒤 `crawlPlayerHistories` 호출하는 지점)에서 아래 후보를 합쳐서 크롤 대상으로 삼는다:

1. `org_player_links`에 `status='confirmed'`인 선수 전원 (기존 로직 그대로 — 항상 포함, 상한 미적용 또는 상한 계산 시 최우선 배정)
2. `org_rankings`(오늘 막 교체된 값) 중, `org_player_history_crawl_state`에 없거나(`last_points`가 없음 = 신규) 있어도 `last_points <> org_rankings.total_points`(변경됨)인 선수 — **상한(cap) 적용, 초과분은 이번 회차 스킵**

두 집합을 `org_player_id` 기준으로 합치고 중복 제거. SQL 한 쿼리로 짤 수도 있고(뷰나 RPC), TS 쪽에서 두 번 조회해 합쳐도 된다 — 기존 코드가 순수 로직을 TS에 두는 편(`dedupeHistoryRows` 등)이라 그 결을 따르는 걸 권장.

우선순위: confirmed 연결자는 상한 밖에서 항상 포함. 변경분 후보는 상한 안에서 처리하되, 순서 기준(예: `last_crawled_at`이 오래된 순, 또는 `org_player_id` 정렬)을 정해서 상한에 걸려 밀린 선수가 다음 회차에 우선권을 갖도록 할 것(그냥 매번 같은 앞부분만 도는 걸 방지).

### 3.3 최초 백필 (일간 크론과 분리)

- 일간 크론에 붙는 상한 로직 그대로 두면 3,546명을 다 채우는 데 상한 수치에 따라 수십 일 걸릴 수 있다. 그건 기능 체감상 너무 느리다.
- 별도의 1회성 백필 경로를 만들 것 — 두 가지 방법 중 택1(구현 세션 판단):
  - (a) 관리자 트리거 가능한 별도 Edge Function/스크립트로, 상한을 훨씬 크게(또는 무제한, 단 요청 간 딜레이 유지) 잡아 여러 번 나눠 수동 실행
  - (b) 첫 N일간만 크론의 상한을 임시로 높게 설정(config/env로 빼서 나중에 낮추기 쉽게)
- 백필 방법과 상관없이 **§3.1 상태 테이블 upsert 로직은 동일하게 태운다** — 백필도 결국 "성공한 선수의 last_points를 기록"하는 같은 경로를 쓴다.

### 3.4 요청 간격

`crawlPlayerHistories`의 페이지 루프(그리고 선수 간 루프)에 짧은 딜레이(100~200ms 권장, 정확한 값은 구현 세션 재량)를 추가한다. 지금은 `for` 루프 안에서 딜레이 없이 바로 `fetch`.

---

## 4. 범위 밖 (건드리지 않음)

- `gnuboard_ranking.ts`의 랭킹표(부서 6개) 크롤 로직 자체 — 안 바뀜, 전원 매일 크롤 계속됨
- `replace_org_ranking_division` RPC, `org_ranking_snapshots` insert 로직 — 안 바뀜
- 개인정보/협회 동의 범위에 대한 정책 재검토 — kimabba가 "일단 하자"로 결론(§2 결정 6)
- PR #468(단체전 중복 dedupe)의 로직 — 그대로 유지, 이 작업은 그 위에 쌓는다. 시작 전 main에 머지됐는지 확인하고, 안 됐으면 그 브랜치 위에서 rebase.

---

## 5. 검증 계획

- `dedupeHistoryRows`처럼 순수 함수 단위로 후보 선정 로직 분리 → `crawler_player_history_test.ts`에 단위 테스트(신규/변경/불변 3케이스 + confirmed 연결자 상한 무관 포함 + 상한 초과 시 스킵)
- `deno test --config deno.json --allow-env --allow-read tests` 전체 통과 확인 (현재 450 passed 기준선)
- 배포 후 `crawl_audit`에서 소요시간(`started_at`~`finished_at`)이 타임아웃 안에 드는지 실측 확인
- 배포 후 며칠 뒤 `org_player_history_crawl_state` 행 수가 늘어나는 속도로 백필 진행 상황 확인 가능

---

## 6. 참고 — 이번에 발견한 실측 수치 (구현 세션이 재확인 없이 바로 쓸 수 있음)

- gj 랭커 1,709명 / jn 랭커 1,837명 / 합계 3,546명
- jn 기준 4일간(08-15~08-19) 포인트 변경 0건 — 평상시 변경분 크롤 부하는 매우 낮을 것으로 예상
- gj 6부서 랭킹 교체 + 소수 이력 크롤 전체 소요 ~3초(2026-08-19 21:00 UTC 실측) — 이건 "확정 연결자 소수"만 돈 경우이므로 전 선수 확장 후엔 당연히 늘어남, 신규 실측 필요
