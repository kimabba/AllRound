# 개인 이력 크롤 — 전 선수 확장 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 협회 랭킹표에 있는 전 선수(현재 3,546명)의 개인 대회 이력을 크롤 대상으로 확장한다. 지금은 `org_player_links.status='confirmed'`로 본인 연결한 소수만 개인 이력이 쌓여, 랭킹 리스트에서 나머지 선수를 탭하면 "아직 협회에 등록된 전적이 없습니다"만 뜬다.

**Architecture:** 크롤 대상 선정을 "confirmed 연결자(항상 포함) + 포인트가 바뀌었거나 신규인 랭커(상한 적용)"로 바꾼다. 마지막으로 이력 크롤을 성공시켰을 때의 포인트를 별도 상태 테이블(`org_player_history_crawl_state`)에 기록해 변경분 판정에 쓴다. 상한을 넘는 후보는 이번 회차에 스킵되고 상태가 안 갱신되므로 다음 회차에 자연히 우선권을 갖는다(별도 큐 테이블 불필요).

**Tech Stack:** Deno Edge Function(TypeScript), PostgreSQL(Supabase), Flutter는 변경 없음.

## Global Constraints

- 이 문서는 이미 kimabba 승인이 난 작업지시서(`docs/superpowers/specs/2026-08-20-org-player-history-full-coverage-design.md`)를 그대로 구현한다 — 설계를 다시 논의하지 않는다.
- 전제조건 PR #468(단체전 중복 dedupe 버그 수정)은 이미 main에 머지됨(2026-08-20) — 확인 완료, 별도 작업 불필요.
- TypeScript: `any` 금지. Dart 영향 없음.
- 신규 SQL 테이블은 RLS enable + 정책 필수(AGENTS.md).
- 회차당 크롤 인원 상한이 있다 — 상한을 넘는 후보는 이번 회차에 빠지고 다음 회차로 자연히 이월된다(별도 큐 불필요).
- 요청 사이에 100~200ms 딜레이를 둔다(현재는 없음).
- 프로덕션 DB에 마이그레이션을 직접 적용하지 않는다 — 마이그레이션 파일 생성까지만 하고, 적용은 PR 머지 후 별도 배포 절차를 따른다.

---

## File Structure

- **Create:** `supabase/migrations/20260825010000_org_player_history_crawl_state.sql` — 상태 테이블 + 상태 기록 RPC.
- **Modify:** `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts` — 후보 선정 순수 함수 추가, `SupabaseLike` 확장, `crawlPlayerHistories` 후보 소스 교체 + 상태 기록 + 요청 간격.
- **Modify:** `supabase/functions/tests/crawler_player_history_test.ts` — `makeDb` 헬퍼 확장(rankings/state/range mock), 기존 rpc 호출 검증부 `.args` 접근으로 수정, 후보 선정 단위테스트 5종 + `fetchAllRows` 단위테스트 2종 + 통합 테스트 2종 추가.

`gnuboard_ranking.ts`의 `crawlPlayerHistories(db, org, base)` 호출부(line 249)는 시그니처가 그대로라 수정하지 않는다.

---

### Task 1: 상태 테이블 + 상태 기록 RPC 마이그레이션

**Files:**
- Create: `supabase/migrations/20260825010000_org_player_history_crawl_state.sql`

**Interfaces:**
- Produces: 테이블 `public.org_player_history_crawl_state(org_code, org_player_id, last_points, last_crawled_at)`, PK `(org_code, org_player_id)`. RPC `public.record_org_player_history_crawl_state(p_org text, p_org_player_id text, p_points int) returns void` — service_role 전용.

- [ ] **Step 1: 마이그레이션 파일 작성**

```sql
-- 개인 이력 크롤 대상을 confirmed 연결자에서 전 선수로 확장하기 위한 상태 테이블.
--
-- 설계: docs/superpowers/specs/2026-08-20-org-player-history-full-coverage-design.md
--
-- "마지막으로 개인 이력 크롤을 성공시켰을 때의 포인트"를 저장해, 다음 회차에
-- org_rankings.total_points 와 비교해 바뀐 선수만 다시 긁는다. 어제-오늘 스냅샷
-- diff 방식은 회차를 건너뛰면 추적이 끊기므로 쓰지 않는다(§3.1).

begin;

create table public.org_player_history_crawl_state (
  org_code        text not null,
  org_player_id   text not null,
  last_points     int not null,
  last_crawled_at timestamptz not null default now(),
  primary key (org_code, org_player_id)
);

comment on table public.org_player_history_crawl_state is
  '개인 이력 크롤러 전용 내부 상태. 마지막으로 이력 크롤을 성공시켰을 때의 total_points 를 기록해 변경분만 다시 크롤하는 데 쓴다. 클라이언트는 읽지 않는다.';

alter table public.org_player_history_crawl_state enable row level security;

-- 클라이언트가 읽을 이유가 없는 순수 내부 테이블이지만, 신규 테이블은 RLS
-- enable + 정책이 필수다(AGENTS.md). crawl_audit(007) 과 같은 관례 —
-- admin 조회만 열어 디버깅 때 확인할 길은 남긴다.
create policy org_player_history_crawl_state_admin_only
  on public.org_player_history_crawl_state
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- authenticated 에 SELECT grant 가 반드시 있어야 한다 — 011_api_role_grants.test.sql
-- assertion 1이 "authenticated 가 SELECT 못 하는 public 테이블이 없다"를 강제한다.
-- 실제 접근 통제는 위 RLS 정책(admin만)이 한다 — "권한은 넓게 + RLS 가 행 통제"
-- 모델(011_api_role_grants 관례)이라 grant 를 넓혀도 새 구멍은 없다.
grant select on public.org_player_history_crawl_state to anon, authenticated;
-- 쓰기는 크롤러(service_role) 전용. service_role 은 rolbypassrls 라 RLS 는
-- 통과하지만 테이블 권한(GRANT)은 별도라 명시해야 한다(011_api_role_grants 관례).
grant select, insert, update on public.org_player_history_crawl_state to service_role;

-- ═══════════════════════════════════════════════
-- 상태 기록 RPC — 크롤러 전용
-- ═══════════════════════════════════════════════
create or replace function public.record_org_player_history_crawl_state(
  p_org           text,
  p_org_player_id text,
  p_points        int
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.org_player_history_crawl_state
    (org_code, org_player_id, last_points, last_crawled_at)
  values (p_org, p_org_player_id, p_points, now())
  on conflict (org_code, org_player_id) do update
    set last_points = excluded.last_points,
        last_crawled_at = excluded.last_crawled_at;
$$;

comment on function public.record_org_player_history_crawl_state is
  '개인 이력 크롤이 성공한 직후 그 선수의 마지막 크롤 시점 포인트를 기록한다. service_role 전용(크롤러).';

revoke execute on function
  public.record_org_player_history_crawl_state(text, text, int)
  from public, anon, authenticated;
grant execute on function
  public.record_org_player_history_crawl_state(text, text, int)
  to service_role;

commit;
```

- [ ] **Step 2: 로컬 스택이 떠 있으면 적용해 문법을 검증한다. 없으면 스킵하고 다음 태스크로.**

Run: `supabase status`
- 로컬 스택이 `RUNNING`이면: `supabase db reset` 실행 후 에러 없이 끝나는지 확인.
- 로컬 스택이 안 떠 있으면(이 레포의 통상 상태): 이 마이그레이션은 **프로덕션에 직접 적용하지 않는다** — PR 머지 후 별도 배포 절차를 따른다는 프로젝트 규칙(START-HERE.md §5-3)을 지킨다. 문법 검증은 Task 4의 `deno check`/`supabase db lint`(있다면)로 대체하거나, PR 리뷰 단계에서 확인한다.

- [ ] **Step 3: 커밋**

```bash
git add supabase/migrations/20260825010000_org_player_history_crawl_state.sql
git commit -m "feat(db): 개인 이력 크롤 상태 테이블 + 기록 RPC 추가"
```

---

### Task 2: 후보 선정 순수 함수 + 단위 테스트 (TDD)

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts`
- Test: `supabase/functions/tests/crawler_player_history_test.ts`

**Interfaces:**
- Consumes: 없음(순수 함수, 이 파일 내부 데이터만).
- Produces:
  - `export interface RankingTotal { orgPlayerId: string; totalPoints: number }`
  - `export interface HistoryCrawlStateRow { orgPlayerId: string; lastPoints: number; lastCrawledAt: string }`
  - `export function selectHistoryCandidates(params: { confirmedOrgPlayerIds: string[]; rankings: RankingTotal[]; state: HistoryCrawlStateRow[]; cap: number }): string[]` — Task 3이 이 함수를 소비한다.

- [ ] **Step 1: 실패하는 테스트 5종 작성**

`supabase/functions/tests/crawler_player_history_test.ts` 맨 위 import 블록의 `import { ... } from '../_shared/crawler/parsers/gnuboard_player_history.ts';` 에 `selectHistoryCandidates` 를 추가한다.

```ts
import {
  crawlPlayerHistories,
  dedupeHistoryRows,
  looksLikeHistoryPage,
  normalizeResultRound,
  parsePlayerHistoryRows,
  playerHistoryUrl,
  selectHistoryCandidates,
  type SupabaseLike,
} from '../_shared/crawler/parsers/gnuboard_player_history.ts';
```

파일 맨 끝(340번째 줄 `});` 다음)에 아래를 추가한다.

```ts
// ── selectHistoryCandidates — confirmed 항상 포함 + 변경분/신규 상한 이월 ──────

Deno.test('selectHistoryCandidates: 신규(상태 없음) 선수는 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 100 }],
    state: [],
    cap: 10,
  });
  assertEquals(result, ['p1']);
});

Deno.test('selectHistoryCandidates: 포인트가 바뀐 선수는 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 200 }],
    state: [{ orgPlayerId: 'p1', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 10,
  });
  assertEquals(result, ['p1']);
});

Deno.test('selectHistoryCandidates: 포인트가 그대로면 제외된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [{ orgPlayerId: 'p1', totalPoints: 100 }],
    state: [{ orgPlayerId: 'p1', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 10,
  });
  assertEquals(result, []);
});

Deno.test('selectHistoryCandidates: confirmed 연결자는 변경 여부·상한과 무관하게 항상 포함된다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: ['pinned'],
    rankings: [{ orgPlayerId: 'pinned', totalPoints: 100 }],
    state: [{ orgPlayerId: 'pinned', lastPoints: 100, lastCrawledAt: '2026-08-20T00:00:00Z' }],
    cap: 0, // 상한을 0으로 줘도 confirmed 는 빠지지 않는다
  });
  assertEquals(result, ['pinned']);
});

Deno.test('selectHistoryCandidates: 상한을 넘는 변경분은 last_crawled_at 이 오래된(또는 없는) 순으로 남긴다', () => {
  const result = selectHistoryCandidates({
    confirmedOrgPlayerIds: [],
    rankings: [
      { orgPlayerId: 'newer', totalPoints: 200 },
      { orgPlayerId: 'older', totalPoints: 300 },
      { orgPlayerId: 'brand-new', totalPoints: 50 },
    ],
    state: [
      { orgPlayerId: 'newer', lastPoints: 100, lastCrawledAt: '2026-08-24T00:00:00Z' },
      { orgPlayerId: 'older', lastPoints: 100, lastCrawledAt: '2026-08-01T00:00:00Z' },
      // brand-new 는 state 자체가 없다 — 가장 오래된 것으로 취급해 최우선.
    ],
    cap: 2,
  });
  assertEquals(result, ['brand-new', 'older']);
});
```

- [ ] **Step 2: 테스트가 실패하는지 확인 (아직 함수가 없으므로 컴파일 에러)**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts`
Expected: FAIL — `selectHistoryCandidates` is not exported / does not exist.

- [ ] **Step 3: `selectHistoryCandidates` 구현**

`supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts` 의 `dedupeHistoryRows` 함수(144~150행) 바로 뒤, `const USER_AGENT = ...`(152행) 바로 앞에 삽입한다.

```ts
export interface RankingTotal {
  orgPlayerId: string;
  totalPoints: number;
}

export interface HistoryCrawlStateRow {
  orgPlayerId: string;
  lastPoints: number;
  lastCrawledAt: string;
}

/**
 * 이번 회차에 개인 이력을 크롤할 선수 목록을 정한다.
 *
 * confirmed 연결자는 상한과 무관하게 항상 포함된다("내 기록" 화면이 직접
 * 의존하므로 놓치면 안 된다). 나머지는 org_rankings 의 total_points 가 state 의
 * last_points 와 다르거나(변경) state 가 아예 없으면(신규) 후보가 되고, cap 을
 * 넘는 만큼은 이번 회차에서 빠진다 — last_crawled_at 이 오래된(또는 아예 없는)
 * 순으로 우선권을 줘서, 상한에 밀린 선수가 다음 회차에 먼저 뽑히게 한다.
 */
export function selectHistoryCandidates(params: {
  confirmedOrgPlayerIds: string[];
  rankings: RankingTotal[];
  state: HistoryCrawlStateRow[];
  cap: number;
}): string[] {
  const { confirmedOrgPlayerIds, rankings, state, cap } = params;
  const confirmed = new Set(confirmedOrgPlayerIds);
  const stateByPlayer = new Map(state.map((s) => [s.orgPlayerId, s]));

  const eligible = rankings.filter((r) => {
    if (confirmed.has(r.orgPlayerId)) return false; // 이미 항상 포함되므로 중복 방지
    const s = stateByPlayer.get(r.orgPlayerId);
    return !s || s.lastPoints !== r.totalPoints;
  });

  eligible.sort((a, b) => {
    const aAt = stateByPlayer.get(a.orgPlayerId)?.lastCrawledAt ?? '';
    const bAt = stateByPlayer.get(b.orgPlayerId)?.lastCrawledAt ?? '';
    if (aAt !== bAt) return aAt < bAt ? -1 : 1;
    return a.orgPlayerId < b.orgPlayerId ? -1 : 1;
  });

  const capped = eligible.slice(0, cap).map((r) => r.orgPlayerId);
  return [...confirmedOrgPlayerIds, ...capped];
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts`
Expected: PASS — 새로 추가한 5개 테스트 포함 전체 통과.

- [ ] **Step 5: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts \
        supabase/functions/tests/crawler_player_history_test.ts
git commit -m "feat(crawler): 개인 이력 크롤 후보 선정 순수 함수 selectHistoryCandidates 추가"
```

---

### Task 3: `crawlPlayerHistories` 후보 소스 교체 + 상태 기록 + 요청 간격

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts`
- Test: `supabase/functions/tests/crawler_player_history_test.ts`

**Interfaces:**
- Consumes: Task 2의 `selectHistoryCandidates`, `RankingTotal`, `HistoryCrawlStateRow`.
- Produces: `crawlPlayerHistories(db: SupabaseLike, org: string, base: string): Promise<string[]>` — 시그니처 불변(호출부 `gnuboard_ranking.ts:249` 수정 불필요). `SupabaseLike.from()` 이 `'org_player_links' | 'org_rankings' | 'org_player_history_crawl_state'` 세 테이블 오버로드를 갖는다(뒤 둘은 `.range()` 포함). `export async function fetchAllRows<T>(fetchPage, pageSize): Promise<{ rows: T[]; error: string | null }>` — PostgREST 1,000행 상한 회피용 페이지네이션 헬퍼, 순수 유틸이라 단독 테스트 가능.

> **⚠️ 2026-08-25 main 최신화 보정:** PR #476(챗봇 온디맨드 이력 조회)이 이 파일을 리팩터링했다 — 페이지 루프가 `fetchPlayerHistory(base, orgPlayerId)` 공유 함수(180~215행)로 분리됐고 `crawlPlayerHistories` 는 그걸 호출한다. **이 리팩터링을 되돌리지 말 것** — 아래 Step 들은 최신 구조 기준으로 갱신됐다. 이 태스크의 구현자는 반드시 현재 파일을 먼저 읽고 라인 번호를 재확인할 것.

- [ ] **Step 1: `SupabaseLike` 인터페이스에 두 읽기 경로 추가 (실패하는 상태로 먼저 인터페이스만 바꾼다)**

`org_rankings` 는 gj 1,709명·jn 1,837명이라 PostgREST 기본 응답 상한(1,000행)에 걸린다 — `.range()` 로 페이지네이션해야 뒤쪽 700~800여 명이 조용히 잘리지 않는다. `org_player_history_crawl_state` 도 백필이 끝나면 같은 규모가 되므로 동일하게 `.range()` 를 둔다.

`gnuboard_player_history.ts` 217~232행의 기존 `SupabaseLike` 정의(`from(table: string)` 단일 시그니처)를 아래로 교체한다.

```ts
/** 이 파일이 DB 에 요구하는 최소 형태. supabase-js 클라이언트가 이걸 만족한다. */
export interface SupabaseLike {
  from(table: 'org_player_links'): {
    select(columns: string): {
      eq(column: string, value: string): {
        eq(column: string, value: string): PromiseLike<
          { data: { org_player_id: string }[] | null; error: { message: string } | null }
        >;
      };
    };
  };
  from(table: 'org_rankings'): {
    select(columns: string): {
      eq(column: string, value: string): {
        range(from: number, to: number): PromiseLike<
          {
            data: { org_player_id: string | null; total_points: number }[] | null;
            error: { message: string } | null;
          }
        >;
      };
    };
  };
  from(table: 'org_player_history_crawl_state'): {
    select(columns: string): {
      eq(column: string, value: string): {
        range(from: number, to: number): PromiseLike<
          {
            data:
              | { org_player_id: string; last_points: number; last_crawled_at: string }[]
              | null;
            error: { message: string } | null;
          }
        >;
      };
    };
  };
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ error: { message: string } | null }>;
}
```

- [ ] **Step 2: 요청 간격 상수 + sleep 헬퍼 + 상한 상수 + 페이지네이션 헬퍼 추가, `fetchPlayerHistory` 에 페이지 딜레이 옵션 추가**

`const MAX_HISTORY_PAGES = 20;`(173행) 바로 뒤에 아래 상수·헬퍼를 추가한다.

그리고 `fetchPlayerHistory`(186행)에 선택적 딜레이 파라미터를 추가한다 — 크롤러는 150ms 딜레이를 넘기고, 챗봇 온디맨드 경로(기존 호출부)는 기본값 0으로 그대로 빨라야 한다. 시그니처를 `fetchPlayerHistory(base: string, orgPlayerId: string, pageDelayMs = 0)` 으로 바꾸고, 페이지 루프 안 `html = await res.text();` 다음에 `if (pageDelayMs > 0) await sleep(pageDelayMs);` 한 줄을 넣는다. 기존 호출부(챗봇 쪽)는 인자 2개라 수정 불필요.

```ts
// 회차당 크롤 인원 상한. 상한을 넘는 변경분/신규 후보는 이번 회차에 빠지고
// last_crawled_at 이 갱신되지 않아 다음 회차에 자연히 우선권을 갖는다(§2 결정3).
// 잘못된/빈 환경변수는 NaN 이 될 수 있어 후보가 조용히 0명이 되는 걸 막는다.
// 배포 후 crawl_audit 의 started_at~finished_at 실측으로 기본값을 튜닝할 것.
const parsedHistoryCap = Number(Deno.env.get('ORG_PLAYER_HISTORY_CAP'));
export const HISTORY_CANDIDATE_CAP =
  Number.isFinite(parsedHistoryCap) && parsedHistoryCap > 0 ? parsedHistoryCap : 100;

// 요청량이 확 늘어나므로(연결자 소수 → 전 선수) 협회 사이트에 대한 예의 차원의 딜레이.
const REQUEST_DELAY_MS = 150;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// PostgREST 기본 응답 상한(1,000행) 회피용 페이지네이션. org_rankings 가
// gj 1,709 / jn 1,837 명이라 한 번에 안 긁으면 뒤쪽 선수가 조용히 잘린다.
export async function fetchAllRows<T>(
  fetchPage: (
    from: number,
    to: number,
  ) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  pageSize: number,
): Promise<{ rows: T[]; error: string | null }> {
  const rows: T[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await fetchPage(from, from + pageSize - 1);
    if (error) return { rows, error: error.message };
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return { rows, error: null };
}

const SUPABASE_PAGE_SIZE = 1000;
```

- [ ] **Step 3: `crawlPlayerHistories` 본문을 후보 소스 교체 + 상태 기록 + 딜레이로 교체**

234~307행(기존 docstring `"연결 승인(confirmed)된 선수의 대회 이력을 수집한다..."` 부터 함수 끝까지)을 아래로 교체한다. 옛 docstring이 이제 사실과 다르므로(confirmed 전용이 아니게 됨) 함께 갈아치운다 — 아래 교체본 맨 위에 새 docstring이 포함돼 있다. **페이지 fetch 는 기존 `fetchPlayerHistory` 를 그대로 호출한다(#476 리팩터링 유지) — 페이지 루프를 다시 인라인하지 말 것.**

```ts
/**
 * 개인 이력 크롤 대상: confirmed 연결자(항상) + 랭킹표 기준 변경분/신규(상한 적용).
 * 상한에 걸려 밀린 후보는 상태가 안 갱신되므로 다음 회차에 자연히 다시 후보가 된다.
 * 한 명이 실패해도 나머지는 계속한다 — 실패는 메시지로 모아 돌려준다.
 */
export async function crawlPlayerHistories(
  db: SupabaseLike,
  org: string,
  base: string,
): Promise<string[]> {
  const failures: string[] = [];

  let confirmedLinks: { org_player_id: string }[] | null;
  try {
    const { data, error } = await db
      .from('org_player_links')
      .select('org_player_id')
      .eq('org_code', org)
      .eq('status', 'confirmed');
    if (error) return [`연결 목록 조회 실패: ${error.message}`];
    confirmedLinks = data;
  } catch (e) {
    // supabase-js 가 에러 객체 대신 예외를 던지는 경로 — 여기서 막지 않으면
    // 랭킹 파서 전체(gnuboardRankingParser)를 뚫고 나가 부서 교체까지 죽인다.
    return [`연결 목록 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  // org_rankings 는 gj 1,709 / jn 1,837명이라 PostgREST 기본 응답 상한(1,000행)을
  // 넘는다 — fetchAllRows 로 안 긁으면 뒤쪽 700~800여 명이 조용히 잘린다.
  let rankingRows: { org_player_id: string | null; total_points: number }[];
  try {
    const result = await fetchAllRows<{ org_player_id: string | null; total_points: number }>(
      (from, to) =>
        db.from('org_rankings').select('org_player_id, total_points').eq('org_code', org).range(
          from,
          to,
        ),
      SUPABASE_PAGE_SIZE,
    );
    if (result.error) return [`랭킹 조회 실패: ${result.error}`];
    rankingRows = result.rows;
  } catch (e) {
    return [`랭킹 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  let stateRows: { org_player_id: string; last_points: number; last_crawled_at: string }[];
  try {
    const result = await fetchAllRows<
      { org_player_id: string; last_points: number; last_crawled_at: string }
    >(
      (from, to) =>
        db.from('org_player_history_crawl_state').select(
          'org_player_id, last_points, last_crawled_at',
        ).eq('org_code', org).range(from, to),
      SUPABASE_PAGE_SIZE,
    );
    if (result.error) return [`크롤 상태 조회 실패: ${result.error}`];
    stateRows = result.rows;
  } catch (e) {
    return [`크롤 상태 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  const rankedRows = rankingRows.filter(
    (r): r is { org_player_id: string; total_points: number } => r.org_player_id != null,
  );
  const pointsByPlayer = new Map(rankedRows.map((r) => [r.org_player_id, r.total_points]));

  const candidateIds = selectHistoryCandidates({
    confirmedOrgPlayerIds: (confirmedLinks ?? []).map((l) => l.org_player_id),
    rankings: rankedRows.map((r) => ({
      orgPlayerId: r.org_player_id,
      totalPoints: r.total_points,
    })),
    state: stateRows.map((s) => ({
      orgPlayerId: s.org_player_id,
      lastPoints: s.last_points,
      lastCrawledAt: s.last_crawled_at,
    })),
    cap: HISTORY_CANDIDATE_CAP,
  });

  if (candidateIds.length === 0) return failures;

  for (const orgPlayerId of candidateIds) {
    // 페이지 fetch·종료·레이아웃 검증은 온디맨드 경로와 공유하는
    // fetchPlayerHistory 가 담당한다(#476). 크롤러만 페이지 간 딜레이를 준다.
    let fetched: PlayerHistoryFetchResult;
    try {
      fetched = await fetchPlayerHistory(base, orgPlayerId, REQUEST_DELAY_MS);
    } catch (e) {
      // 실패한 선수는 상태를 갱신하지 않아 다음 회차에 다시 후보로 잡힌다(§3.1).
      failures.push(
        `이력 ${orgPlayerId} ${e instanceof Error ? e.message : String(e)}`,
      );
      await sleep(REQUEST_DELAY_MS);
      continue;
    }

    // 상한까지 꽉 채우고 끝났다 — 데이터는 있는 만큼 적재하되(아래 계속) 잘렸다는
    // 사실을 알린다. 조용히 뒤쪽 이력이 사라지는 것보다 낫다.
    if (fetched.reachedPageLimit) {
      failures.push(
        `이력 ${orgPlayerId}: ${MAX_HISTORY_PAGES}페이지 상한 도달 — 이후 이력 잘림 가능`,
      );
    }

    // 0행은 그 자체로는 실패가 아니다 — 아직 출전 이력이 없는 선수가 있다.
    if (fetched.rows.length === 0) {
      await sleep(REQUEST_DELAY_MS);
      continue;
    }

    try {
      const { error: rpcErr } = await db.rpc('upsert_org_player_results', {
        p_org: org,
        p_org_player_id: orgPlayerId,
        p_rows: dedupeHistoryRows(fetched.rows).map((r) => ({
          tournament_name: r.tournamentName,
          played_on: r.playedOn,
          event_raw: r.eventRaw,
          result_raw: r.resultRaw,
          result_round: r.resultRound,
          points: r.points,
        })),
      });
      if (rpcErr) {
        failures.push(`이력 ${orgPlayerId}: upsert ${rpcErr.message}`);
      } else {
        // 성공한 선수만 상태를 갱신한다 — 실패한 선수는 손대지 않아 다음 회차에
        // 다시 후보로 잡히게 한다(§3.1). 현재 랭킹표에 없는 선수(탈퇴·랭킹 제외
        // 등)는 비교 기준(total_points)이 없어 기록하지 않는다.
        const currentPoints = pointsByPlayer.get(orgPlayerId);
        if (currentPoints !== undefined) {
          const { error: stateErr } = await db.rpc('record_org_player_history_crawl_state', {
            p_org: org,
            p_org_player_id: orgPlayerId,
            p_points: currentPoints,
          });
          if (stateErr) {
            failures.push(`이력 ${orgPlayerId}: 상태 기록 ${stateErr.message}`);
          }
        }
      }
    } catch (e) {
      // db.rpc 도 예외를 던질 수 있다 — 여기서 막아 랭킹 파서 전체가 죽지 않게 한다.
      failures.push(
        `이력 ${orgPlayerId}: upsert 예외 ${e instanceof Error ? e.message : String(e)}`,
      );
    }

    await sleep(REQUEST_DELAY_MS);
  }

  return failures;
}
```

- [ ] **Step 4: 기존 테스트가 깨지는지 확인 (컴파일 에러 예상 — `makeDb` 가 새 `SupabaseLike` 모양을 아직 못 만족)**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts`
Expected: FAIL — 타입 에러 또는 `db.from('org_rankings')` 관련 런타임 에러.

- [ ] **Step 5: `makeDb` 헬퍼를 세 테이블 모두 지원하도록 확장**

`crawler_player_history_test.ts` 149~179행의 기존 `makeDb` 함수를 아래로 교체한다.

```ts
function makeDb(opts: {
  links?: { org_player_id: string }[];
  rankings?: { org_player_id: string | null; total_points: number }[];
  state?: { org_player_id: string; last_points: number; last_crawled_at: string }[];
  fromThrows?: boolean;
  rpcThrows?: boolean;
}): { db: SupabaseLike; rpcCalls: { fn: string; args: unknown }[] } {
  const rpcCalls: { fn: string; args: unknown }[] = [];
  const db = {
    from(table: string) {
      if (opts.fromThrows) throw new Error('boom: from');
      if (table === 'org_player_links') {
        return {
          select() {
            return {
              eq() {
                return {
                  eq() {
                    return Promise.resolve({ data: opts.links ?? [], error: null });
                  },
                };
              },
            };
          },
        };
      }
      if (table === 'org_rankings') {
        return {
          select() {
            return {
              eq() {
                return {
                  range() {
                    return Promise.resolve({ data: opts.rankings ?? [], error: null });
                  },
                };
              },
            };
          },
        };
      }
      // org_player_history_crawl_state
      return {
        select() {
          return {
            eq() {
              return {
                range() {
                  return Promise.resolve({ data: opts.state ?? [], error: null });
                },
              };
            },
          };
        },
      };
    },
    rpc(fn: string, args: Record<string, unknown>) {
      if (opts.rpcThrows) throw new Error('boom: rpc');
      rpcCalls.push({ fn, args });
      return Promise.resolve({ error: null });
    },
  } as unknown as SupabaseLike;
  return { db, rpcCalls };
}
```

- [ ] **Step 6: `rpcCalls` 모양 변경으로 깨지는 기존 assertion 1곳 수정**

318~340행 근처, `'crawlPlayerHistories: 중복 행이 있어도 upsert 를 1번만 부르고 실패 없이 끝난다'` 테스트 안의 아래 줄을:

```ts
    const args = rpcCalls[0] as { p_rows: unknown[] };
```

다음으로 바꾼다:

```ts
    const args = rpcCalls[0].args as { p_rows: unknown[] };
```

- [ ] **Step 7: `fetchAllRows` 페이지네이션 단위테스트 2종 + 통합 테스트 2종 추가**

파일 끝(Task 2에서 추가한 `selectHistoryCandidates` 테스트들 뒤)에 추가한다. import 블록에 `fetchAllRows` 도 추가한다(Step 1에서 이미 추가한 `selectHistoryCandidates` 옆).

```ts
import {
  crawlPlayerHistories,
  dedupeHistoryRows,
  fetchAllRows,
  looksLikeHistoryPage,
  normalizeResultRound,
  parsePlayerHistoryRows,
  playerHistoryUrl,
  selectHistoryCandidates,
  type SupabaseLike,
} from '../_shared/crawler/parsers/gnuboard_player_history.ts';
```

```ts
// ── fetchAllRows — PostgREST 1,000행 응답 상한 회피 페이지네이션 ──────

Deno.test('fetchAllRows: pageSize 보다 작은 페이지를 받으면 멈춘다 (전체 5건, 페이지 2건씩)', async () => {
  const all = ['a', 'b', 'c', 'd', 'e'];
  let calls = 0;
  const { rows, error } = await fetchAllRows<string>((from, to) => {
    calls++;
    return Promise.resolve({ data: all.slice(from, to + 1), error: null });
  }, 2);
  assertEquals(error, null);
  assertEquals(rows, all);
  assertEquals(calls, 3); // 2+2+1
});

Deno.test('fetchAllRows: 에러가 나면 그때까지 모은 것과 에러 메시지를 함께 돌려준다', async () => {
  let calls = 0;
  const { rows, error } = await fetchAllRows<string>((_from, _to) => {
    calls++;
    if (calls === 2) return Promise.resolve({ data: null, error: { message: 'boom' } });
    return Promise.resolve({ data: ['a', 'b'], error: null });
  }, 2);
  assertEquals(rows, ['a', 'b']);
  assertEquals(error, 'boom');
  assertEquals(calls, 2);
});

// ── crawlPlayerHistories 통합 — 랭킹표 기준 변경분/불변분 판정이 실제로 동작한다 ──

Deno.test('통합: 포인트가 바뀐 비연결 선수도 후보에 포함되어 크롤되고 상태가 기록된다', async () => {
  await withFetch((url) => {
    const page = new URL(url).searchParams.get('page');
    return new Response(page === '1' ? ONE_ROW_HTML : HEADER_ONLY_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({
      links: [],
      rankings: [{ org_player_id: 'newp', total_points: 500 }],
      state: [],
    });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    const fns = rpcCalls.map((c) => c.fn);
    assertEquals(fns.includes('upsert_org_player_results'), true);
    assertEquals(fns.includes('record_org_player_history_crawl_state'), true);
    const stateCall = rpcCalls.find((c) => c.fn === 'record_org_player_history_crawl_state');
    const stateArgs = stateCall?.args as { p_org_player_id: string; p_points: number };
    assertEquals(stateArgs.p_org_player_id, 'newp');
    assertEquals(stateArgs.p_points, 500);
  });
});

Deno.test('통합: 포인트가 그대로인 비연결 선수는 크롤되지 않는다(fetch 호출 없음)', async () => {
  let fetchCalls = 0;
  await withFetch(() => {
    fetchCalls++;
    return new Response(ONE_ROW_HTML, { status: 200 });
  }, async () => {
    const { db, rpcCalls } = makeDb({
      links: [],
      rankings: [{ org_player_id: 'samep', total_points: 100 }],
      state: [
        { org_player_id: 'samep', last_points: 100, last_crawled_at: '2026-08-20T00:00:00Z' },
      ],
    });
    const failures = await crawlPlayerHistories(db, 'gj', 'https://gjtennis.kr');
    assertEquals(failures, []);
    assertEquals(fetchCalls, 0);
    assertEquals(rpcCalls.length, 0);
  });
});
```

- [ ] **Step 8: 전체 테스트 통과 확인**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts`
Expected: PASS — 기존 테스트 전부 + Task 2(5개) + Task 3 Step 7(fetchAllRows 2개 + 통합 2개)에서 추가한 총 9개 신규 테스트 전부 통과.

- [ ] **Step 9: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts \
        supabase/functions/tests/crawler_player_history_test.ts
git commit -m "feat(crawler): 개인 이력 크롤 대상을 confirmed 전용에서 전 선수(변경분+신규)로 확장"
```

---

### Task 4: 전체 체크 + 백필 절차 문서화

**Files:**
- Modify: 없음(검증 전용)

**Interfaces:** 없음.

- [ ] **Step 1: Edge Function 전체 체크**

Run: `cd supabase/functions && deno fmt --check */index.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts && deno lint --config deno.json */index.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts && deno check --config deno.json */index.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts && deno test --config deno.json --allow-env --allow-read tests`
Expected: 전부 통과. `deno fmt --check` 가 포맷 차이를 보고하면 `deno fmt` 로 고친 뒤 재확인.

- [ ] **Step 2: PR 설명에 남길 백필 운영 절차 (코드 변경 아님 — PR 작성 시 사용)**

> **최종 whole-branch 리뷰(Fable, 2026-08-25)가 이 문단의 원안 오류를 잡았다:** 크롤 크론은 15분이 아니라 **하루 1회**(`cron.job` 실측: `0 21 * * *`, 06:00 KST)다. 따라서 cap 100 자연 소화로는 gj 1,709명 ≈ 17일 / jn 1,837명 ≈ 19일 — 스펙 §2 결정 4가 금지한 "수십 일 백필" 그 자체다. 원안의 "별도 수동 개입 불필요"는 폐기.

**백필은 스펙 결정 4의 (a)안 — slug 지정 수동 dispatch 반복 — 으로 진행한다.** `crawl-dispatch` Edge Function 은 body 로 `slug` 를 지정하면 스케줄을 무시하고 그 소스만 즉시 실행한다(`crawl-dispatch/index.ts:135`). 회당 cap(100명)씩 진행되므로:

- `tennis-gwangju` 랭킹 소스를 ~17회, `tennis-jeonnam` 을 ~19회, 사이에 몇 분 간격을 두고 수동 호출한다(하루에 몰아서 해도 되고 며칠 나눠도 된다 — 상태 테이블 기반이라 어디서 끊겨도 이어진다).
- **배포 순서 주의(최종 리뷰 Important #2):** 마이그레이션(`20260825010000`)을 프로덕션에 **먼저** 적용한 뒤 Edge Function 을 배포한다. 순서가 뒤집히면 state 테이블 조회 실패로 confirmed 연결자 크롤까지 멈추는 회귀가 생긴다(랭킹 미러는 무사, failures 로 보고는 됨).
- cap 을 1,000명대로 올리는 방식은 Edge Function wall-clock 한도(400초) 초과 위험이 커서 채택하지 않는다(선수당 페이지 fetch + 150ms 딜레이 × 수백 명).

```sql
-- 읽기 전용 — 백필 진행 상황 확인용
select org_code, count(*) from org_player_history_crawl_state group by org_code;
-- gj 는 1,709, jn 은 1,837 에 수렴하면 백필이 끝난 것이다.
```

PR 설명에는 스펙 §2 결정 6(개인정보/협회 동의 범위 재검토는 이번 스코프에 포함하지 않았고, 나중에 문제되면 되돌릴 수 있다는 배경)을 반드시 남긴다. 배포 다음 날 `crawl_audit` 의 `started_at`~`finished_at` 로 회당 소요시간을 실측 확인한다(스펙 §5).

- [ ] **Step 3: 커밋 없음 — Task 4는 검증/운영 메모 단계다.**

---

## Self-Review 체크리스트 (계획 작성자가 실행, 참고용)

- 스펙 §2 결정 1~5 전부 태스크로 커버됨(결정 6 정책 재검토는 스코프 아웃, 단 PR 설명에 배경은 남기도록 Task 4 Step 2에 명시).
- §3.1 상태 테이블 → Task 1. §3.2 후보 선정 쿼리 → Task 2(순수 함수)+Task 3(통합). §3.3 백필 → Task 4 Step 2(자연 크론 주기로 대체, 수동 cap 상향 안 함). §3.4 요청 간격 → Task 3 Step 2/3.
- §5 검증 계획의 "신규/변경/불변 3케이스 + confirmed 상한 무관 + 상한 초과 스킵" 5종 전부 Task 2에 있음.
- placeholder 없음 — 모든 스텝에 실제 코드/명령 포함.

## Fable 모델 검토 반영 이력 (2026-08-25)

독립 리뷰(claude-fable-5)에서 나온 지적을 아래와 같이 반영했다:
- **[반영]** 마이그레이션에 `authenticated` SELECT grant 누락 — `011_api_role_grants.test.sql` 가드 테스트(assertion 1)가 실패했을 것. Task 1 Step 1에 `grant select ... to anon, authenticated` 추가.
- **[반영]** Task 3 Step 3의 교체 범위가 197행부터였는데 실제로는 192행부터 옛 docstring이 시작돼, 교체 후에도 이제 틀린 docstring이 남았을 것. 192행부터로 수정.
- **[반영]** `org_rankings`/`org_player_history_crawl_state` select가 PostgREST 기본 1,000행 상한에 걸려 gj/jn 각각 700~800여 명이 후보 풀에서 조용히 잘렸을 것 — `fetchAllRows` 페이지네이션 헬퍼(+ 단위테스트 2종) 추가로 해결.
- **[반영]** 백필 cap 을 1,000~2,000으로 올리자던 원안이 Edge Function 타임아웃을 넘길 위험이 있다는 지적 — 기본 cap(100) + 15분 크론만으로 반나절 내 자연 백필된다는 계산으로 대체, 수동 개입 절차 제거.
- **[반영]** `Number(env)` 가 NaN 이 될 수 있다는 지적 — `Number.isFinite` 가드 추가.
- **[미반영, 의도적]** 테스트 스위트에 `sleep(150)` 딜레이가 그대로 걸려 실행이 느려진다는 지적 — 경미하다고 판단해 이번 계획 스코프에서는 반영하지 않음(테스트 케이스 수가 적어 총 지연이 수백 ms 수준).
