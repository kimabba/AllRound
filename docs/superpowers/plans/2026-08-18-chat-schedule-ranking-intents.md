# 챗봇 일정 겹침 확인 / 랭킹 조회 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 챗봇의 `match_schedule` 인텐트(현재 "아직 지원 안 함" 고정 안내문 스텁)를 즐겨찾기 대회·클럽 모임 일정 겹침 확인으로 교체하고, `my_profile` 인텐트 응답에 본인 인증 연결된 협회 랭킹 정보를 추가한다.

**Architecture:** 기존 챗봇은 이미 룰 기반 의도 분류 → 결정론적 DB 조회(RPC) → 카드/텍스트 렌더 라는 구조로 대회검색·클럽검색을 처리하고 있다(신규 설계 불필요, 그대로 재사용). 이번 작업은 그 패턴을 두 곳에 적용하는 것: (1) 이미 존재하는 `match_schedule` 룰 라우팅에 실데이터 조회를 연결, (2) 이미 존재하는 `my_profile` 룰 라우팅(LLM이 결정론적 프로필 컨텍스트를 문장으로 바꿔주는 경로)에 랭킹 섹션을 추가. 새 인텐트나 Gemini function calling은 필요 없다 — 둘 다 기존 룰(`MATCH_KW`+`SCHEDULE_KW`, `MY_PROFILE_KW`)이 이미 커버한다.

**Tech Stack:** Supabase Postgres (pgTAP), Deno Edge Functions (TypeScript), Supabase JS client (`.rpc()`).

## Global Constraints

- 새 RPC는 `security invoker` + `set search_path = public` + `(select auth.uid())` 패턴을 따른다(`my_ranking_candidates` 선례, `supabase/migrations/20260803040000_org_ranking_claim_rpc.sql:23-26`).
- 새 RPC 실행 권한은 `anon`에 주지 않는다. `authenticated`에만 grant, `public`/`anon`에서 명시적으로 revoke한다(`supabase/migrations/20260803060000_revoke_replace_ranking_from_clients.sql:36-37` 선례).
- 정확성이 필요한 계산(날짜 겹침, 랭킹 순위)은 SQL/RPC가 하고 LLM은 계산하지 않는다. `match_schedule` 응답은 카드·클럽 검색과 동일하게 LLM을 호출하지 않는 결정론적 텍스트로 만든다.
- 마이그레이션 파일명은 `YYYYMMDDHHMMSS_설명.sql` 형식(마지막 기존 파일: `20260810130000_org_ranking_snapshots_public_read.sql`). 이 계획은 `20260818120000_`을 쓴다.
- pgTAP 테스트 파일은 `supabase/tests/database/NNN_설명.test.sql` 순번(마지막: `025_club_member_chat.test.sql` → 이 계획은 `026_`을 쓴다).
- Deno lint/fmt 설정은 `supabase/functions/deno.json`(2-space indent, single quote, semicolons, lineWidth 100)을 따른다.

## 설계 문서 대비 범위 조정 (실제 코드 확인 결과)

브레인스토밍 설계 문서(`docs/superpowers/specs/2026-08-18-chat-tournament-schedule-ranking-design.md`)는 `supabase/functions/chat/` 코드를 읽지 못한 상태에서 작성됐다. 이번 계획 작성 중 실제 코드를 확인하고 아래 세 가지를 조정했다:

1. **대회검색/추천은 이미 완전히 구현되어 있다.** `tournament_search` 인텐트가 룰 기반으로 분류되어 `tournament_search_by_slots` RPC로 결정론적으로 검색·카드 응답까지 만든다(`chat/index.ts:781-971`). 설계 문서의 목표 ①은 이미 달성된 상태라 이번 계획에 별도 태스크가 없다.
2. **랭킹조회는 별도 인텐트를 신설하지 않고 기존 `my_profile` 라우팅에 통합했다.** `MY_PROFILE_KW` 룰(`_shared/intent.ts:350`)이 "내 랭킹"을 이미 `my_profile`로 분류하고 있어("내\s*(등급\|점수\|협회\|프로필\|랭킹\|부수)"), 새 인텐트를 만드는 대신 그 라우팅이 만드는 프로필 컨텍스트에 랭킹 섹션을 얹었다(Task 4). 설계 문서 §5의 "조회 처리기 3개(각각 별도)" 구상보다 작은 변경이다.
3. **설계 문서 §9의 "Gemini function calling과 Search Grounding 동시 사용 가능 여부" 질문은 무의미해졌다.** 실제 코드는 애초에 Gemini function calling을 쓰지 않는다 — 룰/임베딩으로 의도를 먼저 분류하고, 라우팅되면 RPC로 결정론적 조회 후 카드나 고정 텍스트로 응답하며 LLM을 아예 호출하지 않는다(`club_search`/`tournament_search`/이번 `match_schedule`). LLM은 `my_profile`·`free_chat`처럼 라우팅되지 않는 경로에서만 호출된다. 이 계획은 그 기존 패턴을 그대로 따른다.

---

### Task 1: DB 마이그레이션 — `my_schedule_conflicts` / `my_confirmed_ranking` RPC

**Files:**
- Create: `supabase/migrations/20260818120000_chat_schedule_ranking_rpcs.sql`
- Test: `supabase/tests/database/026_chat_schedule_ranking_rpcs.test.sql`

**Interfaces:**
- Produces: `public.my_schedule_conflicts(p_horizon_days int default 90)` returns table `(kind text, a_id uuid, a_title text, a_start date, a_end date, b_id uuid, b_title text, b_date date)` — `kind`은 `'tournament_vs_tournament'` 또는 `'tournament_vs_club_event'`.
- Produces: `public.my_confirmed_ranking()` returns table `(org_code text, division_code text, org_player_id text, rank int, rank_points int, total_points int, fetched_at timestamptz)`.
- Both: 인자 없이 `(select auth.uid())`로 호출자 본인 데이터만 반환(RLS와 무관하게 함수 내부에서 필터). `authenticated`만 실행 가능.

- [ ] **Step 1: pgTAP 테스트 작성 (아직 존재하지 않는 함수 대상 — 실패해야 정상)**

`supabase/tests/database/026_chat_schedule_ranking_rpcs.test.sql` 생성:

```sql
create extension if not exists pgtap with schema extensions;

begin;
select plan(11);

select has_function('public', 'my_schedule_conflicts', 'my_schedule_conflicts 함수 존재');
select has_function('public', 'my_confirmed_ranking', 'my_confirmed_ranking 함수 존재');

-- ── 실행 권한 가드 ──────────────────────────────────────────────
select is(
  has_function_privilege('anon', 'public.my_schedule_conflicts(int)', 'EXECUTE'),
  false, 'anon 은 일정겹침 RPC 를 실행할 수 없다');
select is(
  has_function_privilege('authenticated', 'public.my_schedule_conflicts(int)', 'EXECUTE'),
  true, 'authenticated 는 일정겹침 RPC 를 실행할 수 있다');
select is(
  has_function_privilege('anon', 'public.my_confirmed_ranking()', 'EXECUTE'),
  false, 'anon 은 랭킹조회 RPC 를 실행할 수 없다');
select is(
  has_function_privilege('authenticated', 'public.my_confirmed_ranking()', 'EXECUTE'),
  true, 'authenticated 는 랭킹조회 RPC 를 실행할 수 있다');

-- ── 시드 ────────────────────────────────────────────────────────
insert into auth.users (id, email) values
  ('55555555-5555-5555-5555-555555555555', 'sched-a@test.local')
on conflict do nothing;
insert into public.users (id, email, name) values
  ('55555555-5555-5555-5555-555555555555', 'sched-a@test.local', '박일정')
on conflict (id) do update set name = excluded.name;

-- 겹치는 대회 2건(같은 유저가 둘 다 즐겨찾기)
insert into public.tournaments
  (id, sport, title, region, start_date, end_date, status)
values
  ('a0000000-0000-0000-0000-000000000001', 'tennis', '겹침 대회 A', '광주',
   current_date + 10, current_date + 12, 'published'),
  ('a0000000-0000-0000-0000-000000000002', 'tennis', '겹침 대회 B', '광주',
   current_date + 11, current_date + 13, 'published'),
  ('a0000000-0000-0000-0000-000000000003', 'tennis', '안 겹치는 대회 C', '광주',
   current_date + 40, current_date + 41, 'published')
on conflict (id) do nothing;

insert into public.tournament_favorites (user_id, tournament_id) values
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000001'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000002'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000003')
on conflict do nothing;

-- 클럽 + 모임(대회 A 기간 중 하루)
insert into public.clubs (id, sport, name, region, status) values
  ('b0000000-0000-0000-0000-000000000001', 'tennis', '겹침 테스트 클럽', '광주', 'approved')
on conflict (id) do nothing;
insert into public.club_members (club_id, user_id, role, status) values
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'member', 'active')
on conflict do nothing;
insert into public.club_events (club_id, created_by, title, starts_at) values
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '정기 모임', (current_date + 11)::timestamptz + interval '10 hour')
on conflict do nothing;

-- 랭킹: confirmed 링크가 있는 협회만 조회되어야 함
insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 3, '박일정', 'sched_player_1', 900, 900, 'https://x')
on conflict do nothing;
insert into public.org_player_links (org_code, org_player_id, user_id, status) values
  ('gj', 'sched_player_1', '55555555-5555-5555-5555-555555555555', 'confirmed')
on conflict do nothing;

-- ── my_schedule_conflicts: 대회끼리 겹침 1건 + 대회-모임 겹침 1건 ──
set local role authenticated;
set local request.jwt.claims to '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

select is(
  (select count(*)::int from public.my_schedule_conflicts()),
  2, '대회-대회 겹침 1건 + 대회-모임 겹침 1건 = 총 2건');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_tournament'),
  1, '대회끼리 겹침은 1건(A-B, C 는 안 겹침)');

-- ── my_confirmed_ranking: confirmed 링크된 랭킹만 ──────────────────
select is(
  (select count(*)::int from public.my_confirmed_ranking()),
  1, '본인 인증 연결된 랭킹 1건');
select is(
  (select rank from public.my_confirmed_ranking()),
  3, '반환된 순위가 시드값과 일치');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
```

- [ ] **Step 2: 테스트 실행 → 함수 없음으로 실패 확인**

Run: `supabase start` (아직 안 켜져 있다면), 이어서 `bash scripts/qa/run_db_tests.sh`
Expected: `026_chat_schedule_ranking_rpcs.test.sql`가 `has_function` 단언에서 FAIL. (다른 기존 테스트 파일은 그대로 통과해야 한다 — 실패가 이 파일에 국한되는지 확인.)

- [ ] **Step 3: 마이그레이션 작성**

`supabase/migrations/20260818120000_chat_schedule_ranking_rpcs.sql` 생성:

```sql
-- 챗봇 확장 — 일정 겹침 확인 / 랭킹 조회 RPC
--
-- 설계: docs/superpowers/specs/2026-08-18-chat-tournament-schedule-ranking-design.md
--
-- 둘 다 my_ranking_candidates(20260803040000) 패턴을 따른다: 인자로 user_id 를 받지
-- 않고 (select auth.uid()) 로 호출자 본인만 조회한다 — RLS 와 별개로 함수 자체가
-- 다른 사용자 데이터를 반환하지 않음을 보장한다. 앱은 랭킹을 계산하지 않고
-- org_rankings 미러 값을 그대로 옮긴다(테이블 코멘트 참고).

begin;

-- ═══════════════════════════════════════════════
-- my_schedule_conflicts — 즐겨찾기 대회끼리, 그리고 즐겨찾기 대회와
--   내가 속한 클럽의 모임 일정이 겹치는지 확인한다.
-- ═══════════════════════════════════════════════
create or replace function public.my_schedule_conflicts(p_horizon_days int default 90)
returns table (
  kind    text,
  a_id    uuid,
  a_title text,
  a_start date,
  a_end   date,
  b_id    uuid,
  b_title text,
  b_date  date
)
language sql
stable
security invoker
set search_path = public
as $$
  -- 즐겨찾기한 대회끼리 날짜 겹침. f2.tournament_id > f1.tournament_id 로 (A,B)/(B,A)
  -- 중복과 자기 자신(A,A)을 함께 제거한다.
  select
    'tournament_vs_tournament'::text as kind,
    t1.id as a_id, t1.title as a_title, t1.start_date as a_start, t1.end_date as a_end,
    t2.id as b_id, t2.title as b_title, t2.start_date as b_date
  from public.tournament_favorites f1
  join public.tournaments t1 on t1.id = f1.tournament_id
  join public.tournament_favorites f2
    on f2.user_id = f1.user_id and f2.tournament_id > f1.tournament_id
  join public.tournaments t2 on t2.id = f2.tournament_id
  where f1.user_id = (select auth.uid())
    and t1.start_date <= coalesce(t2.end_date, t2.start_date)
    and t2.start_date <= coalesce(t1.end_date, t1.start_date)
    and t1.start_date >= current_date
    and t1.start_date <= current_date + p_horizon_days

  union all

  -- 즐겨찾기한 대회 기간 중 내 클럽(active 멤버) 모임이 있는 경우.
  select
    'tournament_vs_club_event'::text as kind,
    t.id as a_id, t.title as a_title, t.start_date as a_start, t.end_date as a_end,
    e.id as b_id, e.title as b_title, e.starts_at::date as b_date
  from public.tournament_favorites f
  join public.tournaments t on t.id = f.tournament_id
  join public.club_members m on m.user_id = f.user_id and m.status = 'active'
  join public.club_events e on e.club_id = m.club_id
  where f.user_id = (select auth.uid())
    and e.starts_at::date between t.start_date and coalesce(t.end_date, t.start_date)
    and t.start_date >= current_date
    and t.start_date <= current_date + p_horizon_days
$$;

comment on function public.my_schedule_conflicts is
  '호출자가 즐겨찾기한 대회끼리, 그리고 그 대회 기간과 본인이 속한 클럽 모임이 겹치는지 반환. 챗봇 match_schedule 라우팅 전용.';

revoke execute on function public.my_schedule_conflicts(int) from public, anon;
grant execute on function public.my_schedule_conflicts(int) to authenticated;

-- ═══════════════════════════════════════════════
-- my_confirmed_ranking — 본인 인증 연결(confirmed)된 협회 랭킹만 반환.
-- ═══════════════════════════════════════════════
create or replace function public.my_confirmed_ranking()
returns table (
  org_code      text,
  division_code text,
  org_player_id text,
  rank          int,
  rank_points   int,
  total_points  int,
  fetched_at    timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select r.org_code, r.division_code, l.org_player_id, r.rank, r.rank_points, r.total_points, r.fetched_at
  from public.org_player_links l
  join public.org_rankings r
    on r.org_code = l.org_code and r.org_player_id = l.org_player_id
  where l.user_id = (select auth.uid())
    and l.status = 'confirmed'
$$;

comment on function public.my_confirmed_ranking is
  '호출자의 본인 인증 연결(confirmed)된 협회 랭킹만 반환. 연결 없으면 0행. 챗봇 my_profile 라우팅 전용.';

revoke execute on function public.my_confirmed_ranking() from public, anon;
grant execute on function public.my_confirmed_ranking() to authenticated;

commit;
```

- [ ] **Step 4: 테스트 재실행 → 통과 확인**

Run: `bash scripts/qa/run_db_tests.sh`
Expected: `026_chat_schedule_ranking_rpcs.test.sql` 전체 PASS(11/11), 다른 기존 테스트 파일도 계속 PASS.

- [ ] **Step 5: 커밋**

```bash
git add supabase/migrations/20260818120000_chat_schedule_ranking_rpcs.sql \
        supabase/tests/database/026_chat_schedule_ranking_rpcs.test.sql
git commit -m "feat(db): 챗봇용 일정겹침/랭킹조회 RPC 추가"
```

---

### Task 2: 순수 렌더 함수 — `renderScheduleConflictText`

**Files:**
- Modify: `supabase/functions/_shared/chat_cards.ts`
- Test: `supabase/functions/tests/chat_cards_test.ts`

**Interfaces:**
- Consumes: Task 1의 `my_schedule_conflicts` RPC 반환 행 형태 `{ kind, a_id, a_title, a_start, a_end, b_id, b_title, b_date }`.
- Produces: `isScheduleConflictRow(value: unknown): value is ScheduleConflictRow`, `renderScheduleConflictText(rows: ScheduleConflictRow[]): string` — Task 3(`chat/index.ts`)이 그대로 가져다 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`supabase/functions/tests/chat_cards_test.ts` 끝에 추가 (파일 상단 import에 `isScheduleConflictRow, renderScheduleConflictText, type ScheduleConflictRow`를 `'../_shared/chat_cards.ts'`에서 추가):

```ts
Deno.test('renderScheduleConflictText - 겹침 없으면 안내 문구', () => {
  const text = renderScheduleConflictText([]);
  assert(text.includes('겹치는 일정이 없어요'));
});

Deno.test('renderScheduleConflictText - 대회끼리 겹침을 나열', () => {
  const rows: ScheduleConflictRow[] = [
    {
      kind: 'tournament_vs_tournament',
      a_id: 'a1',
      a_title: '광주 오픈',
      a_start: '2026-09-10',
      a_end: '2026-09-11',
      b_id: 'a2',
      b_title: '전남 챔피언십',
      b_date: '2026-09-11',
    },
  ];
  const text = renderScheduleConflictText(rows);
  assert(text.includes('광주 오픈'));
  assert(text.includes('전남 챔피언십'));
  assert(text.includes('대회'));
});

Deno.test('renderScheduleConflictText - 대회-클럽모임 겹침은 라벨을 클럽 모임으로 표기', () => {
  const rows: ScheduleConflictRow[] = [
    {
      kind: 'tournament_vs_club_event',
      a_id: 'a1',
      a_title: '광주 오픈',
      a_start: '2026-09-10',
      a_end: '2026-09-11',
      b_id: 'e1',
      b_title: '정기 모임',
      b_date: '2026-09-10',
    },
  ];
  const text = renderScheduleConflictText(rows);
  assert(text.includes('클럽 모임'));
  assert(text.includes('정기 모임'));
});

Deno.test('isScheduleConflictRow - 필수 필드 누락이면 거부', () => {
  assert(!isScheduleConflictRow({ kind: 'tournament_vs_tournament' }));
  assert(
    isScheduleConflictRow({
      kind: 'tournament_vs_tournament',
      a_id: 'a1',
      a_title: 't',
      a_start: '2026-09-10',
      a_end: null,
      b_id: 'a2',
      b_title: 't2',
      b_date: '2026-09-11',
    }),
  );
});
```

- [ ] **Step 2: 테스트 실행 → 정의되지 않은 심볼로 실패 확인**

Run: `cd supabase/functions && deno test -A tests/chat_cards_test.ts`
Expected: FAIL — `renderScheduleConflictText`, `isScheduleConflictRow`, `ScheduleConflictRow`가 export 되지 않아 타입/런타임 에러.

- [ ] **Step 3: 구현**

`supabase/functions/_shared/chat_cards.ts`의 `renderClubDetailText` 함수 정의 바로 뒤, `export type SelectedEntityType` 앞에 추가:

```ts
// ==========================================================================
// Schedule conflicts (match_schedule 라우팅 — my_schedule_conflicts RPC 결과 렌더)
// ==========================================================================

export interface ScheduleConflictRow {
  kind: 'tournament_vs_tournament' | 'tournament_vs_club_event';
  a_id: string;
  a_title: string;
  a_start: string;
  a_end: string | null;
  b_id: string;
  b_title: string;
  b_date: string;
}

export function isScheduleConflictRow(value: unknown): value is ScheduleConflictRow {
  if (!isRecord(value)) return false;
  return (value.kind === 'tournament_vs_tournament' || value.kind === 'tournament_vs_club_event') &&
    typeof value.a_id === 'string' &&
    typeof value.a_title === 'string' &&
    typeof value.a_start === 'string' &&
    (typeof value.a_end === 'string' || value.a_end === null) &&
    typeof value.b_id === 'string' &&
    typeof value.b_title === 'string' &&
    typeof value.b_date === 'string';
}

/// my_schedule_conflicts RPC 결과를 결정론적 텍스트로 렌더(LLM 미사용, club_search/
/// tournament_search 라우팅과 동일 패턴). rows=[] 는 "비교 대상은 있으나 겹침 없음"
/// 의미다 — "비교할 대상 자체가 없음"은 호출자(chat/index.ts)가 별도로 안내한다.
export function renderScheduleConflictText(rows: ScheduleConflictRow[]): string {
  if (rows.length === 0) {
    return [
      '겹치는 일정이 없어요.',
      '즐겨찾기한 대회와 클럽 모임 일정을 확인했지만 날짜가 겹치는 항목은 없습니다.',
    ].join('\n');
  }
  const lines = rows.map((r) => {
    const bLabel = r.kind === 'tournament_vs_tournament' ? '대회' : '클럽 모임';
    const aRange = r.a_end && r.a_end !== r.a_start ? `${r.a_start} ~ ${r.a_end}` : r.a_start;
    return `- "${r.a_title}"(${aRange})와 ${bLabel} "${r.b_title}"(${r.b_date})가 겹쳐요.`;
  });
  return [`## 일정 겹침 ${rows.length}건`, '', ...lines].join('\n');
}
```

- [ ] **Step 4: 테스트 재실행 → 통과 확인**

Run: `cd supabase/functions && deno test -A tests/chat_cards_test.ts`
Expected: 신규 4개 테스트 포함 전체 PASS.

- [ ] **Step 5: lint/fmt 확인 + 커밋**

Run: `cd supabase/functions && deno fmt --check _shared/chat_cards.ts tests/chat_cards_test.ts && deno lint _shared/chat_cards.ts tests/chat_cards_test.ts`
Expected: 에러 없음 (틀어지면 `deno fmt` 로 해당 파일만 재포맷 후 diff를 눈으로 확인 — 주변 스타일 손대지 않기).

```bash
git add supabase/functions/_shared/chat_cards.ts supabase/functions/tests/chat_cards_test.ts
git commit -m "feat(chat): 일정 겹침 렌더 함수 추가"
```

---

### Task 3: `chat/index.ts` — `match_schedule` 라우팅을 실제 조회로 교체

**Files:**
- Modify: `supabase/functions/chat/index.ts:440-459` (기존 고정 안내문 블록)
- Modify: `supabase/functions/chat/index.ts:37-53` (`_shared/chat_cards.ts` import)

**Interfaces:**
- Consumes: Task 2의 `renderScheduleConflictText`, `isScheduleConflictRow`, `ScheduleConflictRow`; Task 1의 RPC `my_schedule_conflicts`.
- Produces: 없음(엔드포인트 동작 변경만).

- [ ] **Step 1: import 추가**

`supabase/functions/chat/index.ts` 상단의 `_shared/chat_cards.ts` import 블록(현재 17번째 줄 부근, `buildClubCards`로 시작)을 다음으로 교체:

```ts
import {
  buildClubCards,
  buildRefineChip,
  buildTournamentCards,
  type ClubCardRow,
  type ClubDetailRow,
  isGradeRegisteredForSport,
  isScheduleConflictRow,
  isTournamentCardRow,
  parseSelectedEntity,
  parseTournamentRefine,
  renderClubDetailText,
  renderClubSearchEmptyText,
  renderClubSearchText,
  renderScheduleConflictText,
  renderTournamentApplicationGuideText,
  renderTournamentSearchEmptyText,
  renderTournamentSearchText,
  type ScheduleConflictRow,
} from '../_shared/chat_cards.ts';
```

- [ ] **Step 2: 기존 고정 안내문 블록을 실제 조회로 교체**

다음 블록(현재 440-459줄)을:

```ts
        // ---- match_schedule: 개인 매치 일정 데이터 미비 → 결정적 안내 fallback ----
        // RAG 로 흘리면 무관한 대회/룰을 긁어오므로 안내로 종료한다.
        if (intentResult.intent === 'match_schedule') {
          const dr = intentResult.slots.date_range;
          const scheduleText = '개인 매치 일정은 아직 채팅에서 조회할 수 없어요. ' +
            '클럽 모임은 클럽 탭에서, 관심 대회 일정은 대회 즐겨찾기에서 확인하세요.' +
            (dr ? '\n이 기간의 대회가 궁금하면 "이 기간 대회 알려줘"라고 말씀해 주세요.' : '');
          send('context', { tournaments: [], rules: [] });
          send('delta', { text: scheduleText });
          await chatWriter.from('chat_messages').insert({
            user_id: user.id,
            conversation_id: conversationId,
            role: 'assistant',
            content: scheduleText,
            citations: [],
          });
          send('done', {});
          controller.close();
          return;
        }
```

다음으로 교체:

```ts
        // ---- match_schedule: 즐겨찾기 대회 + 클럽 모임 일정 겹침 확인 (LLM 미사용, 결정적) ----
        if (intentResult.intent === 'match_schedule') {
          const { data: conflictRows, error: conflictErr } = await supabase.rpc(
            'my_schedule_conflicts',
          );

          let scheduleText: string;
          if (conflictErr) {
            console.error(
              'chat_route',
              JSON.stringify({
                event: 'schedule_conflicts_rpc_error',
                reason: conflictErr.message,
                user_id_hash: hashedUserId,
                conversation_id: conversationId,
              }),
            );
            scheduleText = '일시적인 시스템 오류로 일정을 확인하지 못했습니다. ' +
              '잠시 후 다시 시도해 주세요.';
          } else {
            const typedRows = (Array.isArray(conflictRows) ? conflictRows : [])
              .filter(isScheduleConflictRow) as ScheduleConflictRow[];
            if (typedRows.length === 0) {
              // 겹침이 0건인 이유가 "비교할 게 없어서"인지 "겹치는 게 없어서"인지 구분해
              // 서로 다른 안내를 준다. club_events 존재 자체는 확인하지 않고(비용 대비
              // 이득이 낮음) 클럽 가입 여부로 근사한다.
              const [{ count: favoriteCount }, { count: activeClubCount }] = await Promise.all([
                supabase
                  .from('tournament_favorites')
                  .select('tournament_id', { count: 'exact', head: true })
                  .eq('user_id', user.id),
                supabase
                  .from('club_members')
                  .select('club_id', { count: 'exact', head: true })
                  .eq('user_id', user.id)
                  .eq('status', 'active'),
              ]);
              scheduleText = (favoriteCount ?? 0) === 0 && (activeClubCount ?? 0) === 0
                ? '비교할 즐겨찾기 대회나 클럽 모임이 없어요. ' +
                  '대회를 즐겨찾기하거나 클럽에 가입하면 겹치는 일정을 확인해 드릴게요.'
                : renderScheduleConflictText([]);
            } else {
              scheduleText = renderScheduleConflictText(typedRows);
            }
          }

          send('context', { tournaments: [], rules: [] });
          send('delta', { text: scheduleText });
          await chatWriter.from('chat_messages').insert({
            user_id: user.id,
            conversation_id: conversationId,
            role: 'assistant',
            content: scheduleText,
            citations: [],
          });
          send('done', {});
          controller.close();
          return;
        }
```

- [ ] **Step 3: Deno 타입체크**

Run: `cd supabase/functions && deno check chat/index.ts`
Expected: 타입 에러 없음.

- [ ] **Step 4: 기존 자동 테스트 회귀 확인**

Run: `cd supabase/functions && deno test -A tests/`
Expected: 전체 PASS (이 태스크는 `chat/index.ts`를 직접 단위테스트하지 않으므로, 여기서 깨지는 게 있다면 Task 1/2의 export 시그니처가 어긋난 것).

- [ ] **Step 5: 커밋**

```bash
git add supabase/functions/chat/index.ts
git commit -m "feat(chat): match_schedule 라우팅에 실제 일정겹침 조회 연결"
```

---

### Task 4: `chat/index.ts` — `my_profile` 응답에 랭킹 섹션 추가

**Files:**
- Modify: `supabase/functions/chat/index.ts:503-532` (`my_profile` 라우팅 블록)
- Modify: `supabase/functions/chat/types.ts` (신규 타입 `MyRankingRow`)

**Interfaces:**
- Consumes: Task 1의 RPC `my_confirmed_ranking`; `TENNIS_ORG_LABELS`(이미 import되어 있음, `_shared/enums.ts`).
- Produces: 없음(엔드포인트 동작 변경만).

- [ ] **Step 1: `MyRankingRow` 타입 추가**

`supabase/functions/chat/types.ts`의 `IntentClassifyRow` 인터페이스 뒤에 추가:

```ts
export interface MyRankingRow {
  org_code: string;
  division_code: string;
  org_player_id: string;
  rank: number;
  rank_points: number;
  total_points: number;
  fetched_at: string;
}
```

- [ ] **Step 2: `chat/index.ts` import에 `MyRankingRow` 추가**

`import type { ChatBody, DbCitation, IntentClassifyRow, ...}` 블록(17번째 줄 근처의 `./types.ts` import)에 `MyRankingRow`를 알파벳 순으로 추가:

```ts
import type {
  ChatBody,
  DbCitation,
  IntentClassifyRow,
  MyRankingRow,
  SemanticRule,
  SemanticTournament,
  UserSport,
  UserTennisOrgRow,
  VenueRow,
} from './types.ts';
```

- [ ] **Step 3: my_profile 블록에 랭킹 섹션 삽입**

기존 코드(현재 522-532줄 부근):

```ts
          if (orgs.length > 0) {
            profileLines.push('');
            profileLines.push('[등록 협회]');
            for (const o of orgs) {
              const orgName = TENNIS_ORG_LABELS[o.org as keyof typeof TENNIS_ORG_LABELS] ?? o.org;
              const division = o.division ?? '미입력';
              const score = o.score !== null ? ` (점수 ${o.score})` : '';
              profileLines.push(`- ${orgName}: ${division}${score}${o.is_primary ? ' ★주' : ''}`);
            }
          }
          const profileContext = profileLines.join('\n');
```

다음으로 교체(랭킹 섹션 삽입, `profileContext` 라인은 그대로 마지막에 유지):

```ts
          if (orgs.length > 0) {
            profileLines.push('');
            profileLines.push('[등록 협회]');
            for (const o of orgs) {
              const orgName = TENNIS_ORG_LABELS[o.org as keyof typeof TENNIS_ORG_LABELS] ?? o.org;
              const division = o.division ?? '미입력';
              const score = o.score !== null ? ` (점수 ${o.score})` : '';
              profileLines.push(`- ${orgName}: ${division}${score}${o.is_primary ? ' ★주' : ''}`);
            }
          }

          // 본인 인증 연결(confirmed)된 랭킹만 표시. 대부분 사용자는 아직 연결이
          // 없어 "조회 불가" 로 나온다 — 알려진 제약(design doc §3 제외 항목).
          const { data: rankingRows, error: rankingErr } = await supabase.rpc(
            'my_confirmed_ranking',
          );
          profileLines.push('');
          profileLines.push('[내 랭킹]');
          if (rankingErr) {
            console.error(
              'chat_route',
              JSON.stringify({
                event: 'my_confirmed_ranking_rpc_error',
                reason: rankingErr.message,
                user_id_hash: hashedUserId,
                conversation_id: conversationId,
              }),
            );
            profileLines.push('- 랭킹 조회 중 오류가 발생해 표시할 수 없음');
          } else {
            const typedRanking = (rankingRows ?? []) as MyRankingRow[];
            if (typedRanking.length === 0) {
              profileLines.push('- 아직 협회 랭킹 본인 인증 연결이 되어 있지 않아 조회할 수 없음');
            } else {
              for (const r of typedRanking) {
                const orgName = TENNIS_ORG_LABELS[r.org_code as keyof typeof TENNIS_ORG_LABELS] ??
                  r.org_code;
                profileLines.push(
                  `- ${orgName} ${r.division_code}: ${r.rank}위 ` +
                    `(순위포인트 ${r.rank_points}, 전체포인트 ${r.total_points})`,
                );
              }
            }
          }

          const profileContext = profileLines.join('\n');
```

- [ ] **Step 4: Deno 타입체크**

Run: `cd supabase/functions && deno check chat/index.ts chat/types.ts`
Expected: 타입 에러 없음.

- [ ] **Step 5: 기존 자동 테스트 회귀 확인 + lint/fmt**

Run: `cd supabase/functions && deno test -A tests/ && deno fmt --check chat/index.ts chat/types.ts && deno lint chat/index.ts chat/types.ts`
Expected: 전체 PASS, lint/fmt 에러 없음.

- [ ] **Step 6: 커밋**

```bash
git add supabase/functions/chat/index.ts supabase/functions/chat/types.ts
git commit -m "feat(chat): my_profile 응답에 본인 랭킹 섹션 추가"
```

---

### Task 5: 인텐트 회귀 테스트 고정 + 전체 DB/Deno 테스트

**Files:**
- Modify: `supabase/functions/tests/intent_test.ts`

**Interfaces:**
- Consumes: `classifyByRule`(`_shared/intent.ts`, 이미 import됨) — 이번 작업은 새 룰을 추가하지 않는다. "내 랭킹"이 이미 `MY_PROFILE_KW`(`/내\s*(등급|점수|협회|프로필|랭킹|부수)/`)로 `my_profile`에 걸린다는 **기존 동작을 고정**하는 회귀 테스트만 추가한다 — 이 테스트가 깨지면 Task 4가 더 이상 트리거되지 않는다는 신호다.

- [ ] **Step 1: 회귀 케이스 추가**

`supabase/functions/tests/intent_test.ts`의 `CASES` 배열에 `my_profile` 관련 기존 케이스들 근처에 추가:

```ts
  {
    msg: '내 랭킹 몇 점이야',
    intent: 'my_profile',
    slots: {},
  },
```

- [ ] **Step 2: 테스트 실행 → 통과 확인 (이미 룰이 커버하므로 새로 실패할 이유 없음 — 통과하지 않으면 기존 룰이 바뀐 것이므로 원인 조사)**

Run: `cd supabase/functions && deno test -A tests/intent_test.ts`
Expected: PASS.

- [ ] **Step 3: 전체 회귀 (Deno + DB)**

Run:
```bash
cd supabase/functions && deno test -A tests/
bash scripts/qa/run_db_tests.sh
```
Expected: 둘 다 전체 PASS.

- [ ] **Step 4: 커밋**

```bash
git add supabase/functions/tests/intent_test.ts
git commit -m "test(chat): 내 랭킹 질문이 my_profile로 분류됨을 고정"
```

---

### Task 6: 수동 스모크 검증 (persona-sim)

**Files:** 없음(코드 변경 없음, 로컬 검증만).

**Interfaces:** 없음.

- [ ] **Step 1: 로컬 스택 기동 + 시드**

`scripts/qa/persona-sim/README.md`의 "실행 (0부터)" 섹션을 따른다:

```bash
supabase start
export ANON_KEY=$(supabase status -o env | grep ANON_KEY | cut -d'"' -f2)
```

- [ ] **Step 2: 즐겨찾기 대회 2건(겹치는 날짜)을 가진 테스트 유저로 챗봇에 "이번 달 매치 일정 겹치는거 있어?" 질문**

```bash
cd scripts/qa/persona-sim
RESP=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/signup" -H "apikey: $ANON_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"email":"smoke-schedule@example.com","password":"Passw0rd!23","data":{"birth_date":"1990-01-01"}}')
TOKEN=$(echo "$RESP" | grep -o '"access_token":"[^"]*"' | head -1 | cut -d'"' -f4)
deno run -A sim.ts chat "$TOKEN" "이번 달 매치 일정 겹치는거 있어?" tennis
```

Expected: 종목/즐겨찾기 미등록 상태이므로 "비교할 즐겨찾기 대회나 클럽 모임이 없어요..." 안내가 반환된다(즐겨찾기 데이터가 없는 새 유저이므로 이 분기가 정상). 에러 없이 SSE 응답이 오는지, `intent: match_schedule`로 분류되는지만 확인한다.

- [ ] **Step 3: "내 랭킹 몇 점이야" 질문으로 my_profile 확장 확인**

```bash
deno run -A sim.ts chat "$TOKEN" "내 랭킹 몇 점이야" tennis
```

Expected: `intent: my_profile`로 분류되고, 응답에 "아직 협회 랭킹 본인 인증 연결이 되어 있지 않아" 취지의 문장이 포함된다(신규 유저는 연결이 없으므로 이 분기가 정상).

- [ ] **Step 4: 결과를 커밋 메시지나 PR 본문에 남길 필요는 없음 — 이상 있으면 해당 Task로 돌아가 수정**

이 태스크는 커밋할 파일이 없다. 문제를 발견하면 원인이 된 Task(1~4)로 돌아가 수정하고 그 Task의 커밋에 fixup한다.
