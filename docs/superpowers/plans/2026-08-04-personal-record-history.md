# 개인 기록장 (1단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 협회 랭킹에 본인을 연결한 사용자가 자기 대회 전적과 "최고의 순간"을 앱에서 보게 한다. 동시에 순위 스냅샷 적재를 시작해 2단계(순위 그래프)의 데이터를 쌓기 시작한다.

**Architecture:** 두 원천을 쓴다. (1) 협회 개인 이력 페이지(`sub4_6_rank.php?userid=`)를 **연결 승인자만** 크롤해 `org_player_results` 에 적재 — 과거 기록이 즉시 채워진다. (2) 순위 스냅샷은 크롤이 아니라 기존 `replace_org_ranking_division` RPC **안에서** 같은 트랜잭션으로 `org_ranking_snapshots` 에 복사한다 — 새 HTTP 요청 0건, 새 cron 0개.

**Tech Stack:** Postgres(Supabase) + pgTAP · Deno Edge Functions · Flutter/Riverpod

## Global Constraints

- 스펙: `docs/superpowers/specs/2026-08-03-personal-record-history-design.md`
- **앱은 점수를 계산하지 않는다.** 협회 공표값을 그대로 옮긴다. 자체 레벨·XP 금지 (스펙 결정 3)
- **새 테이블은 RLS 필수.** 정책에 `TO authenticated` 를 **명시**한다 — 생략하면 PUBLIC 이 되어 anon 조회가 42501 로 죽는다 (#365)
- **새 함수는 grant 를 같은 마이그레이션에 명시**한다. 회수 시엔 `from public, anon, authenticated` 셋 다 떼고 필요한 롤에 다시 부여한다 (#379)
- **TypeScript `any` 금지, Dart `dynamic` 회피** (CLAUDE.md 최소 규칙 3)
- **Edge 커밋 전 `deno fmt --check` · `deno lint` · `deno test` 셋 다** — CI 가 fmt 를 검사한다
- **Flutter 는 `dart format` 을 돌리지 않는다** — 로컬 포매터가 CI 와 달라 파일 전체가 재포맷된다. 주변 스타일에 손으로 맞춘다
- **파싱 실패를 추측값으로 채우지 않는다.** `result_round` 는 NULL 로 두고 `result_raw` 원문을 남긴다
- 연결 상태 값은 `pending` / `confirmed` / `rejected` — `approved` 가 아니다

---

## File Structure

| 파일 | 책임 |
|---|---|
| `supabase/migrations/20260804010000_personal_record_history.sql` | 테이블 2개 + RLS + 스냅샷 적재(기존 RPC 확장) + 적재 RPC |
| `supabase/tests/database/023_personal_record_history.test.sql` | RLS 격리 · 스냅샷 적재 · 멱등성 |
| `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts` | 개인 이력 HTML → 행 배열 (순수 함수) + 연결자 순회 수집 |
| `supabase/functions/tests/fixtures/gj_player_history.html` | 익명화된 실제 마크업 |
| `supabase/functions/tests/crawler_player_history_test.ts` | 파서 테스트 |
| `supabase/functions/_shared/crawler/parsers/gnuboard_ranking.ts` | (수정) 부서 순회 끝에 개인 이력 수집 호출 |
| `app/lib/models/player_result.dart` | 개인 전적 모델 |
| `app/lib/services/ranking_api.dart` | (수정) 내 전적 조회 |
| `app/lib/widgets/profile/my_record_widgets.dart` | 내 기록 섹션 위젯 |
| `app/lib/screens/profile_screen.dart:400` | (수정) 섹션 교체 |

---

### Task 1: 테이블 · RLS · 스냅샷 적재

**Files:**
- Create: `supabase/migrations/20260804010000_personal_record_history.sql`
- Test: `supabase/tests/database/023_personal_record_history.test.sql`

**Interfaces:**
- Consumes: 기존 `org_player_links(org_code, org_player_id, user_id, status)`, `org_rankings`, `replace_org_ranking_division(text,text,text,jsonb)`
- Produces: 테이블 `org_player_results`, `org_ranking_snapshots`; 함수 `upsert_org_player_results(p_org text, p_org_player_id text, p_rows jsonb) returns int` (service_role 전용)

- [ ] **Step 1: 실패하는 pgTAP 테스트를 쓴다**

`supabase/tests/database/023_personal_record_history.test.sql`:

```sql
-- 개인 기록장 — 테이블 격리와 스냅샷 적재 (#JY 개인기록장 1단계)
--
-- 지키는 것 셋:
--   1) 내 전적만 보인다 (남의 org_player_id 행은 안 보인다)
--   2) anon 조회가 에러가 아니라 0행이다 (#365 함정)
--   3) 랭킹 교체가 스냅샷을 남기고, 같은 날 두 번 돌아도 행이 안 는다

create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

-- ── 픽스처: 두 사용자, 각자 다른 협회 선수에 연결 ────────────────
set local role postgres;

insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'zz_mine',   '00000000-0000-4000-8000-000000000002', 'confirmed'),
       ('gj', 'zz_theirs', '00000000-0000-4000-8000-000000000003', 'confirmed');

insert into public.org_player_results
  (org_code, org_player_id, tournament_name, played_on, event_raw, result_raw, result_round, points)
values ('gj', 'zz_mine',   'zz 내 대회',   '2026-05-01', '골드부', '1',    1,    1000),
       ('gj', 'zz_mine',   'zz 내 대회2',  '2026-06-01', '골드부', '16강', 16,   60),
       ('gj', 'zz_theirs', 'zz 남의 대회', '2026-05-01', '골드부', '1',    1,    1000);

-- 1) 내 전적만 보인다
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.org_player_results),
  2,
  '연결 승인된 본인 전적 2건만 보인다'
);

-- 2) 남의 행은 안 보인다
select is(
  (select count(*)::int from public.org_player_results where org_player_id = 'zz_theirs'),
  0,
  '남의 org_player_id 전적은 보이지 않는다'
);

-- 3) anon 은 에러가 아니라 0행이다
reset role;
set local role anon;
select is(
  (select count(*)::int from public.org_player_results),
  0,
  'anon 은 전적을 0행으로 본다 (42501 로 죽지 않는다)'
);
select is(
  (select count(*)::int from public.org_ranking_snapshots),
  0,
  'anon 은 스냅샷을 0행으로 본다 (42501 로 죽지 않는다)'
);

-- 4) 랭킹 교체가 스냅샷을 남긴다
--    `perform` 은 plpgsql 전용이라 .sql 파일에서 쓰면 문법 오류다. 평범한 select 로 부른다.
reset role;
set local role postgres;
select public.replace_org_ranking_division(
  'gj', 'zz_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz선수","org_player_id":"zz_mine",
     "club_raw":null,"rank_points":100,"total_points":100}]'::jsonb
);
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  1,
  '부서 교체가 오늘자 스냅샷 1행을 남긴다'
);

-- 5) 같은 날 두 번 돌아도 안 는다
select public.replace_org_ranking_division(
  'gj', 'zz_div', 'https://example.test/zz',
  '[{"rank":2,"player_name":"zz선수","org_player_id":"zz_mine",
     "club_raw":null,"rank_points":90,"total_points":90}]'::jsonb
);
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  1,
  '같은 날 재크롤해도 스냅샷 행이 늘지 않는다'
);

select * from finish();
rollback;
```

- [ ] **Step 2: 실패를 확인한다**

```bash
supabase start -x edge-runtime,imgproxy,vector,logflare,studio
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/tests/database/023_personal_record_history.test.sql
```

Expected: `ERROR: relation "public.org_player_results" does not exist`

- [ ] **Step 3: 마이그레이션을 쓴다**

`supabase/migrations/20260804010000_personal_record_history.sql`:

```sql
-- 개인 기록장 1단계 — 개인 전적 + 순위 스냅샷
--
-- 설계: docs/superpowers/specs/2026-08-03-personal-record-history-design.md
--
-- 두 테이블이 서로 다른 것을 담는다.
--   org_player_results : 협회 개인 이력 페이지에서 온 대회별 성적. 과거 포함.
--                        여기 'result'는 그 대회 진출 라운드(1=우승, 4=4강)이지
--                        부서 내 랭킹 순위가 아니다.
--   org_ranking_snapshots : 부서 내 순위·누적 포인트의 시간 축. 지금부터 쌓인다.
--                        실명을 담지 않는다 — org_player_id 만.

begin;

-- ═══════════════════════════════════════════════
-- 1) 개인 대회 전적
-- ═══════════════════════════════════════════════
create table public.org_player_results (
  id              uuid primary key default uuid_generate_v7(),
  org_code        text not null,
  org_player_id   text not null,
  tournament_name text not null,
  played_on       date not null,
  event_raw       text,
  -- 협회 표기 원문. '1'·'4'·'16' 과 '16강'·'4강' 이 한 컬럼에 섞여 온다.
  -- 정규화에 실패해도 원문은 남긴다 — 나중에 소급 정규화할 수 있게.
  result_raw      text not null,
  -- 진출 라운드 정규화값(1=우승, 2=준우승, 4=4강 …). 못 읽으면 NULL.
  -- 추측값이나 0으로 채우지 않는다.
  result_round    int,
  points          int not null default 0,
  fetched_at      timestamptz not null default now(),
  unique (org_code, org_player_id, tournament_name, played_on)
);

-- 화면이 항상 "내 것 전부를 최신순"으로 읽는다.
create index org_player_results_player_idx
  on public.org_player_results (org_code, org_player_id, played_on desc);

alter table public.org_player_results enable row level security;

-- TO authenticated 를 명시한다. 생략하면 PUBLIC 이 되어 anon 조회가
-- is_admin() 권한 오류(42501)로 죽는다 — #365 에서 33개 테이블이 이 함정에 걸렸다.
create policy org_player_results_own_select on public.org_player_results
  for select to authenticated
  using (exists (
    select 1 from public.org_player_links l
     where l.org_code = org_player_results.org_code
       and l.org_player_id = org_player_results.org_player_id
       and l.user_id = (select auth.uid())
       and l.status = 'confirmed'
  ));

create policy org_player_results_admin_all on public.org_player_results
  for all to authenticated
  using (is_admin()) with check (is_admin());

-- 쓰기는 크롤러(service_role) 전용. service_role 은 rolbypassrls 라 정책이 없어도 통과한다.

-- ═══════════════════════════════════════════════
-- 2) 순위 스냅샷
-- ═══════════════════════════════════════════════
create table public.org_ranking_snapshots (
  id            uuid primary key default uuid_generate_v7(),
  org_code      text not null,
  division_code text not null,
  org_player_id text not null,
  captured_on   date not null,
  rank          int not null,
  total_points  int not null,
  -- 제약에 이름을 준다. 자동 생성 이름은 길이 제한에 잘려 예측이 안 되고,
  -- 검증 단계에서 이 제약을 떼었다 붙였다 해야 한다.
  constraint org_ranking_snapshots_daily_key
    unique (org_code, division_code, org_player_id, captured_on)
);

create index org_ranking_snapshots_player_idx
  on public.org_ranking_snapshots (org_code, org_player_id, captured_on);

alter table public.org_ranking_snapshots enable row level security;

create policy org_ranking_snapshots_own_select on public.org_ranking_snapshots
  for select to authenticated
  using (exists (
    select 1 from public.org_player_links l
     where l.org_code = org_ranking_snapshots.org_code
       and l.org_player_id = org_ranking_snapshots.org_player_id
       and l.user_id = (select auth.uid())
       and l.status = 'confirmed'
  ));

create policy org_ranking_snapshots_admin_all on public.org_ranking_snapshots
  for all to authenticated
  using (is_admin()) with check (is_admin());

-- 클라이언트 롤 테이블 권한 — 이 레포 모델은 "권한은 넓게 + 행 통제는 RLS".
-- 권한이 없으면 RLS 이전에 permission denied 로 죽는다(011_api_role_grants).
grant select on public.org_player_results, public.org_ranking_snapshots
  to anon, authenticated;
grant all on public.org_player_results, public.org_ranking_snapshots
  to service_role;

-- ═══════════════════════════════════════════════
-- 3) 스냅샷 적재 — 기존 교체 RPC 안에서 같은 트랜잭션으로
-- ═══════════════════════════════════════════════
-- 별도 호출 지점을 만들지 않는 이유:
--   · 부서 교체 직후라 모든 스냅샷 행이 방금 크롤한 값이다
--   · 0행 가드로 건너뛴 부서는 RPC 자체가 안 불려 낡은 값이 오늘 날짜로 안 박힌다
--   · 교체가 롤백되면 스냅샷도 롤백된다
create or replace function public.replace_org_ranking_division(
  p_org        text,
  p_division   text,
  p_source_url text,
  p_rows       jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted int;
begin
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    raise exception 'replace_org_ranking_division: 빈 목록으로 % / % 를 교체할 수 없다',
      p_org, p_division;
  end if;

  delete from public.org_rankings
  where org_code = p_org and division_code = p_division;

  insert into public.org_rankings
    (org_code, division_code, rank, player_name, org_player_id,
     club_raw, rank_points, total_points, source_url)
  select
    p_org, p_division,
    (r ->> 'rank')::int,
    r ->> 'player_name',
    r ->> 'org_player_id',
    r ->> 'club_raw',
    (r ->> 'rank_points')::int,
    (r ->> 'total_points')::int,
    p_source_url
  from jsonb_array_elements(p_rows) as r;

  -- row_count 는 직전 문장 것이다. 아래 스냅샷 insert 보다 반드시 먼저 읽는다.
  get diagnostics v_inserted = row_count;

  -- 하루 1행. on conflict do nothing 이라 그날 첫 크롤 값이 남는다(덮지 않는다).
  insert into public.org_ranking_snapshots
    (org_code, division_code, org_player_id, captured_on, rank, total_points)
  select r.org_code, r.division_code, r.org_player_id,
         current_date, r.rank, r.total_points
    from public.org_rankings r
   where r.org_code = p_org and r.division_code = p_division
     and r.org_player_id is not null
  on conflict do nothing;

  return v_inserted;
end;
$$;

comment on function public.replace_org_ranking_division is
  '한 협회·부서의 랭킹 미러를 한 트랜잭션으로 교체하고 그날치 스냅샷을 남긴다. service_role 전용(크롤러).';

-- create or replace 는 기존 ACL 을 유지하지만, 20260803060000 이 회수한 상태가
-- 유지되는지는 020_ranking_rpc_grants 가 지킨다. 여기서 다시 명시해 의도를 남긴다.
revoke execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  to service_role;

-- ═══════════════════════════════════════════════
-- 4) 개인 전적 적재 RPC — 크롤러 전용
-- ═══════════════════════════════════════════════
create or replace function public.upsert_org_player_results(
  p_org           text,
  p_org_player_id text,
  p_rows          jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    return 0;  -- 전적이 없는 선수는 정상이다. 예외로 만들지 않는다.
  end if;

  insert into public.org_player_results
    (org_code, org_player_id, tournament_name, played_on,
     event_raw, result_raw, result_round, points, fetched_at)
  select
    p_org, p_org_player_id,
    r ->> 'tournament_name',
    (r ->> 'played_on')::date,
    r ->> 'event_raw',
    r ->> 'result_raw',
    nullif(r ->> 'result_round', '')::int,
    coalesce((r ->> 'points')::int, 0),
    now()
  from jsonb_array_elements(p_rows) as r
  on conflict (org_code, org_player_id, tournament_name, played_on)
  do update set
    event_raw    = excluded.event_raw,
    result_raw   = excluded.result_raw,
    result_round = excluded.result_round,
    points       = excluded.points,
    fetched_at   = excluded.fetched_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.upsert_org_player_results is
  '연결 승인자 1명의 협회 대회 전적을 적재한다. 협회가 성적을 정정할 수 있어 갱신한다. service_role 전용(크롤러).';

revoke execute on function
  public.upsert_org_player_results(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.upsert_org_player_results(text, text, jsonb)
  to service_role;

commit;
```

- [ ] **Step 4: 적용하고 테스트를 통과시킨다**

```bash
supabase db reset
bash scripts/qa/run_db_tests.sh
```

Expected: `023_personal_record_history.test.sql ok=6`, 전체 통과

- [ ] **Step 5: 변이 주입으로 역검증한다 — 초록불은 증거가 아니다**

세 개를 각각 깨뜨려 해당 단언이 뒤집히는지 본다. 확인 후 반드시 원복한다.

```bash
DB=postgresql://postgres:postgres@127.0.0.1:54322/postgres
run() { psql "$DB" -q -f supabase/tests/database/023_personal_record_history.test.sql 2>&1 | grep -E '^ (ok|not ok)'; }

# 변이 1: RLS 를 끄면 남의 전적이 보여야 한다 → 단언 1·2 뒤집힘
psql "$DB" -qc 'alter table public.org_player_results disable row level security;'
run
psql "$DB" -qc 'alter table public.org_player_results enable row level security;'

# 변이 2: 정책을 PUBLIC 으로 되돌리면 anon 이 42501 로 죽어야 한다 → 단언 3 뒤집힘
psql "$DB" -qc 'alter policy org_player_results_admin_all on public.org_player_results to public;'
run
psql "$DB" -qc 'alter policy org_player_results_admin_all on public.org_player_results to authenticated;'

# 변이 3: 유니크 제약을 떼면 같은 날 두 번에 행이 늘어야 한다 → 단언 6 뒤집힘
#   on conflict do nothing 은 충돌할 제약이 없으면 아무것도 막지 못한다.
psql "$DB" -qc 'alter table public.org_ranking_snapshots drop constraint org_ranking_snapshots_daily_key;'
run
psql "$DB" -qc 'alter table public.org_ranking_snapshots
  add constraint org_ranking_snapshots_daily_key
  unique (org_code, division_code, org_player_id, captured_on);'
```

Expected: 각 변이에서 지정한 단언만 `not ok`, 원복 후 전부 `ok`

- [ ] **Step 6: 커밋**

```bash
git add supabase/migrations/20260804010000_personal_record_history.sql \
        supabase/tests/database/023_personal_record_history.test.sql
git commit -m "feat(db): 개인 전적·순위 스냅샷 테이블 + 스냅샷 적재

랭킹 교체 RPC 안에서 같은 트랜잭션으로 스냅샷을 남긴다 — 새 호출 지점도
새 cron 도 만들지 않는다. 0행 가드로 건너뛴 부서는 RPC 가 안 불려 낡은 값이
오늘 날짜로 박히지 않는다.

정책에 TO authenticated 를 명시했다(#365). 변이 주입 3건으로 역검증."
```

---

### Task 2: 개인 이력 파서

**Files:**
- Create: `supabase/functions/tests/fixtures/gj_player_history.html`
- Create: `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts`
- Test: `supabase/functions/tests/crawler_player_history_test.ts`

**Interfaces:**
- Produces: `parsePlayerHistoryRows(html: string): PlayerHistoryRow[]`, `interface PlayerHistoryRow { tournamentName: string; playedOn: string; eventRaw: string | null; resultRaw: string; resultRound: number | null; points: number }`

- [ ] **Step 1: 실제 마크업을 확보하고 익명화한다**

**이 저장소는 공개다.** 실명 + 개인 대회 이력을 그대로 커밋하지 않는다. 구조만 남기고 식별 정보를 바꾼다.

```bash
# 실제 org_player_id 하나를 고른다 (DB 에 3,540행 있다)
PID=$(psql "$DATABASE_URL" -tAc \
  "select org_player_id from org_rankings where org_code='gj' and org_player_id is not null limit 1")

curl -s -A 'MatchUpBot/1.0 (+https://matchup.app)' \
  "https://gjtennis.kr/sub4_6_rank.php?userid=${PID}" \
  -o /tmp/player_history_raw.html

# 구조를 확인한다 — 컬럼 순서와 태그를 눈으로 본다
grep -o '<t[dr][^>]*>' /tmp/player_history_raw.html | sort | uniq -c | head
```

원본을 보고 **선수명·아이디·소속을 가짜 값으로 치환**한 뒤 `supabase/functions/tests/fixtures/gj_player_history.html` 로 저장한다. 대회명·날짜·포인트는 구조 검증에 필요하므로 형태를 유지하되 대회명은 가공한다.

**픽스처에 반드시 포함할 것**: 순위 표기가 `1` 형태인 행과 `16강` 형태인 행이 **둘 다** 있어야 한다. 원본에 하나만 있으면 다른 하나를 손으로 추가한다 — 혼재가 이 파서의 핵심 위험이다.

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`supabase/functions/tests/crawler_player_history_test.ts`:

```ts
import { assertEquals } from 'std/assert/mod.ts';
import {
  normalizeResultRound,
  parsePlayerHistoryRows,
} from '../_shared/crawler/parsers/gnuboard_player_history.ts';

const html = await Deno.readTextFile(
  new URL('./fixtures/gj_player_history.html', import.meta.url),
);

Deno.test('개인 이력 행을 파싱한다', () => {
  const rows = parsePlayerHistoryRows(html);
  assertEquals(rows.length > 0, true);
  assertEquals(typeof rows[0].tournamentName, 'string');
  assertEquals(/^\d{4}-\d{2}-\d{2}$/.test(rows[0].playedOn), true);
});

Deno.test('맨숫자 표기를 진출 라운드로 정규화한다', () => {
  assertEquals(normalizeResultRound('1'), 1);
  assertEquals(normalizeResultRound('2'), 2);
  assertEquals(normalizeResultRound('4'), 4);
  assertEquals(normalizeResultRound('16'), 16);
});

Deno.test('N강 표기를 같은 값으로 정규화한다', () => {
  assertEquals(normalizeResultRound('16강'), 16);
  assertEquals(normalizeResultRound('4강'), 4);
  assertEquals(normalizeResultRound('32강'), 32);
});

Deno.test('우승·준우승 표기를 정규화한다', () => {
  assertEquals(normalizeResultRound('우승'), 1);
  assertEquals(normalizeResultRound('준우승'), 2);
});

Deno.test('못 읽는 표기는 NULL 이다 — 추측값으로 채우지 않는다', () => {
  assertEquals(normalizeResultRound('예선탈락'), null);
  assertEquals(normalizeResultRound(''), null);
  assertEquals(normalizeResultRound('-'), null);
});

Deno.test('정규화에 실패해도 원문은 남는다', () => {
  const oddRow = `
    <table><tr>
      <td>zz대회</td><td>예선탈락</td><td>골드부</td><td>5</td><td>2026-05-01</td>
    </tr></table>`;
  const rows = parsePlayerHistoryRows(oddRow);
  assertEquals(rows[0].resultRound, null);
  assertEquals(rows[0].resultRaw, '예선탈락');
});

Deno.test('천 단위 콤마를 제거한다', () => {
  const row = `
    <table><tr>
      <td>zz대회</td><td>1</td><td>골드부</td><td>1,000</td><td>2026-05-01</td>
    </tr></table>`;
  assertEquals(parsePlayerHistoryRows(row)[0].points, 1000);
});
```

- [ ] **Step 3: 실패를 확인한다**

```bash
cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts
```

Expected: FAIL — 모듈을 찾을 수 없음

- [ ] **Step 4: 파서를 구현한다**

`supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts`:

```ts
// _shared/crawler/parsers/gnuboard_player_history.ts
//
// 협회 개인 대회 이력 parser.
//   URL: {base}/sub4_6_rank.php?userid={org_player_id}
//   컬럼: 대회명 | 순위 | 종목 | 포인트 | 대회일
//
// 랭킹표 parser 와 같은 이유로 DOM 을 만들지 않고 정규식으로 행 단위 스캔한다
// (deno-dom 은 WASM 힙에 트리를 올려 Edge 리소스 한도를 넘긴 실측이 있다).
//
// 주의: 여기 '순위'는 그 대회 진출 라운드(1=우승, 4=4강)이지 부서 내 랭킹 순위가 아니다.
//   표기가 '1'·'4'·'16' 과 '16강'·'4강'·'32강' 으로 섞여 온다(선행 설계 §2.2 실측).
//   못 읽으면 NULL 로 두고 원문을 남긴다 — 추측값으로 채우지 않는다.
//
// 설계: docs/superpowers/specs/2026-08-03-personal-record-history-design.md

const ROW_RE = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
const CELL_RE = /<td\b[^>]*>([\s\S]*?)<\/td>/gi;

const ENTITY_MAP: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  '#39': "'",
  nbsp: ' ',
};

function decodeEntities(s: string): string {
  return s.replace(/&(#39|amp|lt|gt|quot|nbsp);/g, (_, name: string) => ENTITY_MAP[name]);
}

function textOf(cellHtml: string): string {
  return decodeEntities(cellHtml.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function toPoints(raw: string): number {
  const n = Number.parseInt(raw.replace(/[^0-9]/g, ''), 10);
  return Number.isNaN(n) ? 0 : n;
}

/** '2026-05-01' | '2026.05.01' | '2026/05/01' → '2026-05-01'. 못 읽으면 null. */
function normalizeDate(raw: string): string | null {
  const m = raw.match(/(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/);
  if (!m) return null;
  const [, y, mo, d] = m;
  return `${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}`;
}

/**
 * 진출 라운드 정규화. '1'→1, '16강'→16, '우승'→1, '준우승'→2.
 * 읽을 수 없으면 null — 0 이나 추측값으로 채우지 않는다.
 */
export function normalizeResultRound(raw: string): number | null {
  const s = raw.trim();
  if (s === '') return null;
  if (s.includes('준우승')) return 2;
  if (s.includes('우승')) return 1;
  const m = s.match(/^(\d+)\s*강?$/);
  if (!m) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isInteger(n) && n > 0 ? n : null;
}

export interface PlayerHistoryRow {
  tournamentName: string;
  playedOn: string; // 'YYYY-MM-DD'
  eventRaw: string | null;
  resultRaw: string;
  resultRound: number | null;
  points: number;
}

/** 개인 이력 HTML → 행 배열. 순수 함수(네트워크·DB 없음)라 테스트가 이것만 본다. */
export function parsePlayerHistoryRows(html: string): PlayerHistoryRow[] {
  const out: PlayerHistoryRow[] = [];

  ROW_RE.lastIndex = 0;
  let rowMatch: RegExpExecArray | null;
  while ((rowMatch = ROW_RE.exec(html)) !== null) {
    const cells: string[] = [];
    CELL_RE.lastIndex = 0;
    let cellMatch: RegExpExecArray | null;
    while ((cellMatch = CELL_RE.exec(rowMatch[1])) !== null) {
      cells.push(cellMatch[1]);
    }
    if (cells.length < 5) continue; // 헤더·안내 행

    const tournamentName = textOf(cells[0]);
    const playedOn = normalizeDate(textOf(cells[4]));
    // 대회명과 대회일이 없으면 유니크 키를 만들 수 없다 — 저장하지 않는다.
    if (!tournamentName || !playedOn) continue;

    const eventRaw = textOf(cells[2]);
    const resultRaw = textOf(cells[1]);

    out.push({
      tournamentName,
      playedOn,
      eventRaw: eventRaw === '' ? null : eventRaw,
      resultRaw,
      resultRound: normalizeResultRound(resultRaw),
      points: toPoints(textOf(cells[3])),
    });
  }
  return out;
}
```

**주의**: Step 1 에서 확인한 실제 컬럼 순서가 위 인덱스(`0`=대회명 … `4`=대회일)와 다르면 **인덱스를 실제에 맞춘다.** 스펙에 적힌 순서는 문서 기준이고 마크업이 정본이다.

- [ ] **Step 5: 테스트를 통과시키고 검사 셋을 돌린다**

```bash
cd supabase/functions
deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts
deno fmt --check _shared/crawler/parsers/gnuboard_player_history.ts tests/crawler_player_history_test.ts
deno lint --config deno.json _shared/crawler/parsers/gnuboard_player_history.ts
```

Expected: 전부 PASS. `deno fmt --check` 를 빠뜨리면 CI 에서 막힌다.

- [ ] **Step 6: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts \
        supabase/functions/tests/crawler_player_history_test.ts \
        supabase/functions/tests/fixtures/gj_player_history.html
git commit -m "feat(crawler): 협회 개인 대회 이력 파서

순위 표기가 '1'·'16강' 으로 섞여 오는 걸 진출 라운드로 정규화하고,
못 읽으면 NULL 로 두고 원문을 남긴다. 픽스처는 실명·아이디를 익명화했다
(공개 저장소)."
```

---

### Task 3: 연결 승인자 이력 수집을 크롤 사이클에 붙인다

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_player_history.ts` (수집 함수 추가)
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_ranking.ts:227` (부서 루프 뒤)
- Test: `supabase/functions/tests/crawler_player_history_test.ts` (추가)

**Interfaces:**
- Consumes: `parsePlayerHistoryRows`, RPC `upsert_org_player_results(text,text,jsonb)`
- Produces: `crawlPlayerHistories(db: SupabaseLike, org: string, base: string): Promise<string[]>` — 실패 메시지 배열을 돌려준다(빈 배열이면 전부 성공)

- [ ] **Step 1: 실패하는 테스트를 쓴다 (수집 대상 선정 로직)**

fetch 는 IO 라 테스트하지 않는다. **URL 을 만드는 규칙**만 순수 함수로 떼어내 검증한다.

`supabase/functions/tests/crawler_player_history_test.ts` 에 추가:

```ts
import { playerHistoryUrl } from '../_shared/crawler/parsers/gnuboard_player_history.ts';

Deno.test('개인 이력 URL 을 만든다', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr', 'vudghk2116'),
    'https://gjtennis.kr/sub4_6_rank.php?userid=vudghk2116',
  );
});

Deno.test('base 의 후행 슬래시를 정리한다', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr/', 'abc'),
    'https://gjtennis.kr/sub4_6_rank.php?userid=abc',
  );
});

Deno.test('아이디를 URL 인코딩한다', () => {
  assertEquals(
    playerHistoryUrl('https://gjtennis.kr', 'a b&c'),
    'https://gjtennis.kr/sub4_6_rank.php?userid=a%20b%26c',
  );
});
```

- [ ] **Step 2: 실패를 확인한다**

```bash
cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/crawler_player_history_test.ts
```

Expected: FAIL — `playerHistoryUrl` 없음

- [ ] **Step 3: 수집 함수를 구현한다**

`gnuboard_player_history.ts` 끝에 추가:

```ts
const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};

export function playerHistoryUrl(base: string, orgPlayerId: string): string {
  return `${base.replace(/\/+$/, '')}/sub4_6_rank.php?userid=${
    encodeURIComponent(orgPlayerId)
  }`;
}

/** 이 파일이 DB 에 요구하는 최소 형태. supabase-js 클라이언트가 이걸 만족한다. */
interface SupabaseLike {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        eq(column: string, value: string): PromiseLike<
          { data: { org_player_id: string }[] | null; error: { message: string } | null }
        >;
      };
    };
  };
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ error: { message: string } | null }>;
}

/**
 * 연결 승인(confirmed)된 선수의 대회 이력을 수집한다.
 * 요청 수 = 승인자 수. 승인자가 없으면 요청 0건으로 즉시 끝난다.
 * 한 명이 실패해도 나머지는 계속한다 — 실패는 메시지로 모아 돌려준다.
 */
export async function crawlPlayerHistories(
  db: SupabaseLike,
  org: string,
  base: string,
): Promise<string[]> {
  const failures: string[] = [];

  const { data: links, error } = await db
    .from('org_player_links')
    .select('org_player_id')
    .eq('org_code', org)
    .eq('status', 'confirmed');

  if (error) return [`연결 목록 조회 실패: ${error.message}`];
  if (!links || links.length === 0) return failures;

  for (const link of links) {
    const url = playerHistoryUrl(base, link.org_player_id);
    let html: string;
    try {
      const res = await fetch(url, { headers: COMMON_HEADERS });
      if (!res.ok) {
        failures.push(`이력 ${link.org_player_id}: HTTP ${res.status}`);
        continue;
      }
      html = await res.text();
    } catch (e) {
      failures.push(
        `이력 ${link.org_player_id}: ${e instanceof Error ? e.message : String(e)}`,
      );
      continue;
    }

    const rows = parsePlayerHistoryRows(html);
    // 0행은 실패가 아니다 — 아직 출전 이력이 없는 선수가 있다.
    // 다만 기존 데이터를 지우지 않는다(upsert 라 애초에 지우지 않는다).
    if (rows.length === 0) continue;

    const { error: rpcErr } = await db.rpc('upsert_org_player_results', {
      p_org: org,
      p_org_player_id: link.org_player_id,
      p_rows: rows.map((r) => ({
        tournament_name: r.tournamentName,
        played_on: r.playedOn,
        event_raw: r.eventRaw,
        result_raw: r.resultRaw,
        result_round: r.resultRound,
        points: r.points,
      })),
    });
    if (rpcErr) failures.push(`이력 ${link.org_player_id}: upsert ${rpcErr.message}`);
  }

  return failures;
}
```

- [ ] **Step 4: 랭킹 파서에서 호출한다**

`gnuboard_ranking.ts` 의 부서 `for` 루프가 끝난 **직후**, `return` 앞에 넣는다:

```ts
  // 부서 교체가 끝난 뒤 연결 승인자의 개인 대회 이력을 수집한다.
  // 요청 수 = 승인자 수라 부담이 작다(선행 설계가 이 크롤을 미룬 이유였던
  // '선수당 1요청 × 수천 명'이 연결자 한정에는 해당하지 않는다).
  // 이력 수집 실패가 랭킹 미러링 성공을 뒤집지 않게 failures 에만 합친다.
  failures.push(...await crawlPlayerHistories(db, org, base));
```

import 를 파일 상단에 추가한다:

```ts
import { crawlPlayerHistories } from './gnuboard_player_history.ts';
```

**여기서 기존 status 판정이 깨진다.** 지금은 `failures.length === Object.keys(MEMBER_KIND_SUFFIX).length` 로 "부서 7개가 전부 실패했나"를 본다. 이력 실패가 같은 배열에 섞이면 그 비교가 의미를 잃는다(이력 실패 7건만으로 `error` 가 될 수 있다).

부서 실패만 따로 센다. `gnuboard_ranking.ts` 를 세 군데 고친다.

1) 루프 시작 전, `const failures: string[] = [];` 아래에 추가:

```ts
  // 부서 실패만 따로 센다 — 아래 status 판정이 "부서 전부 실패"를 뜻하기 때문이다.
  // 개인 이력 실패는 failures 에는 남기되 이 카운터에는 넣지 않는다.
  let divisionFailures = 0;
```

2) 부서 루프 안의 `failures.push(...)` **네 곳**(HTTP 실패 · fetch 예외 · 파싱 0행 · replace 실패) 바로 뒤에 `divisionFailures++;` 를 넣는다.

3) 마지막 `return` 의 status 를 바꾼다:

```ts
    status: divisionFailures === Object.keys(MEMBER_KIND_SUFFIX).length ? 'error' : 'ok',
```

- [ ] **Step 5: 테스트·검사를 돌린다**

```bash
cd supabase/functions
deno test --config deno.json --allow-env --allow-read tests
deno fmt --check */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno lint --config deno.json _shared/crawler/parsers/*.ts
deno check --config deno.json _shared/crawler/parsers/*.ts
```

Expected: 전부 PASS

- [ ] **Step 6: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/
git add supabase/functions/tests/crawler_player_history_test.ts
git commit -m "feat(crawler): 연결 승인자 개인 이력 수집을 랭킹 크롤에 붙인다

요청 수 = 승인자 수. 이력 실패가 랭킹 미러링 성공을 뒤집지 않도록
부서 실패 개수를 따로 세어 status 를 판정한다."
```

---

### Task 4: Flutter 모델 · API

**Files:**
- Create: `app/lib/models/player_result.dart`
- Modify: `app/lib/services/ranking_api.dart`
- Test: `app/test/models/player_result_test.dart`

**Interfaces:**
- Produces: `PlayerResult` 모델, `RankingApi.myPlayerResults()`, `RankingApi.myConfirmedLink()`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`app/test/models/player_result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/player_result.dart';

void main() {
  test('JSON 을 모델로 옮긴다', () {
    final r = PlayerResult.fromJson(const {
      'org_code': 'gj',
      'org_player_id': 'abc',
      'tournament_name': '광주시장배',
      'played_on': '2026-05-01',
      'event_raw': '골드부',
      'result_raw': '1',
      'result_round': 1,
      'points': 1000,
    });
    expect(r.tournamentName, '광주시장배');
    expect(r.playedOn, DateTime(2026, 5, 1));
    expect(r.resultRound, 1);
    expect(r.points, 1000);
  });

  test('정규화 실패 행은 resultRound 가 null 이고 원문이 남는다', () {
    final r = PlayerResult.fromJson(const {
      'org_code': 'gj',
      'org_player_id': 'abc',
      'tournament_name': 'zz',
      'played_on': '2026-05-01',
      'result_raw': '예선탈락',
      'result_round': null,
      'points': 5,
    });
    expect(r.resultRound, isNull);
    expect(r.resultRaw, '예선탈락');
  });

  test('표시 라벨 — 정규화값이 있으면 한국어로, 없으면 원문 그대로', () {
    expect(_label('1', 1), '우승');
    expect(_label('2', 2), '준우승');
    expect(_label('4강', 4), '4강');
    expect(_label('16', 16), '16강');
    expect(_label('예선탈락', null), '예선탈락');
  });
}

String _label(String raw, int? round) => PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': 'zz',
      'played_on': '2026-05-01',
      'result_raw': raw,
      'result_round': round,
      'points': 0,
    }).resultLabel;
```

- [ ] **Step 2: 실패를 확인한다**

```bash
cd app && flutter test test/models/player_result_test.dart
```

Expected: FAIL — `player_result.dart` 없음

- [ ] **Step 3: 모델을 구현한다**

`app/lib/models/player_result.dart`:

```dart
/// 협회가 공표한 개인 대회 전적 1건. 앱이 계산한 값이 아니다.
///
/// `resultRound` 는 그 대회 진출 라운드(1=우승, 2=준우승, 4=4강)이지
/// 부서 내 랭킹 순위가 아니다. 협회 표기를 못 읽으면 null 이고,
/// 그때는 `resultRaw` 원문을 그대로 보여준다.
class PlayerResult {
  const PlayerResult({
    required this.orgCode,
    required this.orgPlayerId,
    required this.tournamentName,
    required this.playedOn,
    required this.resultRaw,
    required this.points,
    this.eventRaw,
    this.resultRound,
  });

  final String orgCode;
  final String orgPlayerId;
  final String tournamentName;
  final DateTime playedOn;
  final String resultRaw;
  final int points;
  final String? eventRaw;
  final int? resultRound;

  factory PlayerResult.fromJson(Map<String, dynamic> j) {
    return PlayerResult(
      orgCode: j['org_code'] as String,
      orgPlayerId: j['org_player_id'] as String,
      tournamentName: j['tournament_name'] as String,
      playedOn: DateTime.parse(j['played_on'] as String),
      resultRaw: j['result_raw'] as String,
      points: (j['points'] as int?) ?? 0,
      eventRaw: j['event_raw'] as String?,
      resultRound: j['result_round'] as int?,
    );
  }

  /// 화면 표기. 정규화가 안 된 행은 협회 원문을 그대로 쓴다 — 빈칸이나 추측값 금지.
  String get resultLabel => switch (resultRound) {
        1 => '우승',
        2 => '준우승',
        final int n => '$n강',
        null => resultRaw,
      };

  bool get isWin => resultRound == 1;
}
```

- [ ] **Step 4: 테스트를 통과시킨다**

```bash
cd app && flutter test test/models/player_result_test.dart
```

Expected: PASS

- [ ] **Step 5: API 를 추가한다**

`app/lib/services/ranking_api.dart` 의 `claimRanking` 아래에 추가하고, 파일 상단 import 에 `import '../models/player_result.dart';` 를 넣는다:

```dart
  /// 내 협회 전적 전량(최신 대회순). RLS 가 연결 승인된 본인 것만 돌려준다.
  Future<List<PlayerResult>> myPlayerResults() async {
    final rows = await supabase
        .from('org_player_results')
        .select()
        .order('played_on', ascending: false);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(PlayerResult.fromJson).toList();
  }

  /// 내 확정 연결 1건(없으면 null). 기록 화면이 연결 여부로 갈리므로 필요하다.
  Future<Map<String, dynamic>?> myConfirmedLink() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final rows = await supabase
        .from('org_player_links')
        .select('org_code, org_player_id')
        .eq('user_id', userId)
        .eq('status', 'confirmed')
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  /// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
  /// 한 선수가 여러 부서 랭킹에 오를 수 있어 목록으로 돌려준다.
  Future<List<OrgRankingRow>> myCurrentRankings() async {
    final link = await myConfirmedLink();
    if (link == null) return const [];
    final rows = await supabase
        .from('org_rankings')
        .select()
        .eq('org_code', link['org_code'] as String)
        .eq('org_player_id', link['org_player_id'] as String)
        .order('division_code');
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(OrgRankingRow.fromJson).toList();
  }
```

- [ ] **Step 6: 전체 테스트를 돌리고 커밋**

로컬 Flutter 가 CI SDK 보다 구버전이라 **부분 테스트로는 컴파일 차이를 못 잡는다.** 반드시 전체를 돌린다.

```bash
cd app && flutter analyze && flutter test
git add app/lib/models/player_result.dart app/lib/services/ranking_api.dart \
        app/test/models/player_result_test.dart
git commit -m "feat(app): 개인 전적 모델·API

정규화 실패 행은 협회 원문을 그대로 표시한다(추측값 금지)."
```

---

### Task 5: 내 기록 섹션 — 미연결 유도 + 1단계 블록

**Files:**
- Create: `app/lib/widgets/profile/my_record_widgets.dart`
- Modify: `app/lib/state/providers.dart` (프로바이더 2개 추가)
- Modify: `app/lib/screens/profile_screen.dart:400`
- Test: `app/test/widgets/my_record_section_test.dart`

**Interfaces:**
- Consumes: `PlayerResult`, `RankingApi.myPlayerResults()`, `RankingApi.myConfirmedLink()`
- Produces: `MyRecordSection` 위젯

- [ ] **Step 1: 실패하는 위젯 테스트를 쓴다**

테스트에 `AppTheme` 을 반드시 넣는다 — 이 프로젝트 테마가 버튼 폭을 무한으로 강제해서, 테마 없이 통과한 위젯이 실기기에서 크래시한 전례가 있다.

`app/test/widgets/my_record_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/models/org_ranking.dart';
import 'package:matchup/models/player_result.dart';
import 'package:matchup/theme/app_theme.dart';
import 'package:matchup/widgets/profile/my_record_widgets.dart';

// AppTheme.light 는 게터가 아니라 메서드다(app/lib/theme/app_theme.dart:9).
// 테마를 빼면 안 된다 — 이 프로젝트 테마가 버튼 폭을 무한으로 강제해서,
// 테마 없이 통과한 위젯이 실기기에서 크래시한 전례가 있다.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

PlayerResult _r({
  required String name,
  required String raw,
  int? round,
  required int points,
  required String on,
}) =>
    PlayerResult.fromJson({
      'org_code': 'gj',
      'org_player_id': 'a',
      'tournament_name': name,
      'played_on': on,
      'result_raw': raw,
      'result_round': round,
      'points': points,
    });

OrgRankingRow _rank({required String div, required int rank, required int pts}) =>
    OrgRankingRow.fromJson({
      'org_code': 'gj',
      'division_code': div,
      'rank': rank,
      'player_name': 'zz선수',
      'rank_points': pts,
      'total_points': pts,
    });

void main() {
  testWidgets('현재 순위 블록을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(
      results: const [],
      rankings: [_rank(div: 'gj_m_gold', rank: 12, pts: 1500)],
    )));
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('1500'), findsWidgets);
  });

  testWidgets('전적이 있으면 최고의 순간과 타임라인을 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '광주시장배', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
      _r(name: '봄철대회', raw: '16강', round: 16, points: 60, on: '2026-03-01'),
    ])));
    expect(find.text('광주시장배'), findsWidgets);
    expect(find.text('우승'), findsWidgets);
    expect(find.text('16강'), findsWidgets);
  });

  testWidgets('최고의 순간은 포인트가 가장 높은 대회다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: '작은대회', raw: '4강', round: 4, points: 100, on: '2026-06-01'),
      _r(name: '큰대회', raw: '1', round: 1, points: 1000, on: '2026-05-01'),
    ])));
    expect(find.textContaining('큰대회'), findsWidgets);
  });

  testWidgets('정규화 실패 행은 협회 원문을 그대로 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(RecordContent(results: [
      _r(name: 'zz대회', raw: '예선탈락', round: null, points: 5, on: '2026-05-01'),
    ])));
    expect(find.text('예선탈락'), findsWidgets);
  });

  testWidgets('전적이 없으면 안내를 보여준다', (tester) async {
    await tester.pumpWidget(_wrap(const RecordContent(results: [])));
    expect(find.textContaining('전적'), findsWidgets);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
cd app && flutter test test/widgets/my_record_section_test.dart
```

Expected: FAIL — `my_record_widgets.dart` 없음

- [ ] **Step 3: 프로바이더를 추가한다**

`app/lib/state/providers.dart` 의 `myTournamentRecordsProvider` 아래:

```dart
/// 내 협회 전적(연결 승인된 경우에만 행이 온다)
final myPlayerResultsProvider =
    FutureProvider<List<PlayerResult>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myPlayerResults();
});

/// 내 확정 연결 — 없으면 연결 유도를 띄운다
final myConfirmedLinkProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myConfirmedLink();
});

/// 연결된 내 현재 순위(부서별). 스펙 §7.2 블록 1 "지금".
final myCurrentRankingsProvider =
    FutureProvider<List<OrgRankingRow>>((ref) async {
  ref.watch(authStateProvider);
  final api = ref.watch(apiProvider);
  return api.myCurrentRankings();
});
```

상단 import 에 `'../models/player_result.dart'` 를 추가한다. `OrgRankingRow` 는
`'../models/org_ranking.dart'` 에 있으므로 이미 import 돼 있지 않으면 함께 추가한다.

- [ ] **Step 4: 위젯을 구현한다**

`app/lib/widgets/profile/my_record_widgets.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// 경로는 profile_records_widgets.dart 의 import 를 그대로 따른다(실측 확인).
//   AppCard/AppCardVariant → widgets/app_card.dart
//   AppSpacing             → theme/tokens.dart
//   SectionHeader          → profile/profile_settings_widgets.dart
import '../../models/org_ranking.dart';
import '../../models/player_result.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../utils/grade_labels.dart'; // divisionLabel
import '../app_card.dart';
import 'profile_settings_widgets.dart';

/// 프로필의 "내 기록" 섹션.
///
/// 연결 승인 전에는 연결 유도를, 승인 후에는 협회 전적을 보여준다.
/// 순위 관련 블록(라이프베스트·추이)은 스냅샷이 쌓인 뒤 2단계에서 붙인다 —
/// 지금 빈 그래프를 그리지 않는다.
class MyRecordSection extends ConsumerWidget {
  const MyRecordSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(myConfirmedLinkProvider);
    final results = ref.watch(myPlayerResultsProvider);
    final rankings = ref.watch(myCurrentRankingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '내 기록'),
        const SizedBox(height: AppSpacing.md),
        link.when(
          loading: () => const _RecordSkeleton(),
          error: (_, __) => const _RecordMessage('기록을 불러오지 못했습니다.'),
          data: (l) => l == null
              ? const _ConnectPrompt()
              : results.when(
                  loading: () => const _RecordSkeleton(),
                  error: (_, __) => const _RecordMessage('기록을 불러오지 못했습니다.'),
                  // 순위 조회가 실패해도 전적은 보여준다 — 둘은 독립적이다.
                  data: (rows) => RecordContent(
                    results: rows,
                    rankings: rankings.valueOrNull ?? const [],
                  ),
                ),
        ),
      ],
    );
  }
}

/// 연결 전 — 여기서 막히면 기능 전체가 죽는다. 무엇을 얻는지 먼저 말한다.
class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AppCard(
      variant: AppCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('협회 기록을 가져오세요', style: tt.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '협회 랭킹에서 본인을 확인하면 지금까지의 대회 전적이 채워집니다.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => context.push('/rankings'),
              child: const Text('협회 랭킹에서 찾기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 연결 후 본문. 상태를 안 들고 있어 위젯 테스트가 이것만 검증한다.
class RecordContent extends StatelessWidget {
  const RecordContent({
    super.key,
    required this.results,
    this.rankings = const [],
  });

  final List<PlayerResult> results;
  final List<OrgRankingRow> rankings;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // 블록 1 "지금" — 현재 순위. 전적이 없어도 이건 보여준다(연결만 되면 나온다).
    final nowBlock = rankings.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...rankings.map((r) => AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(divisionLabel(r.divisionCode), style: tt.labelLarge),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${r.rank}위', style: tt.titleMedium),
                        Text('${r.totalPoints}점', style: tt.bodyLarge),
                      ],
                    ),
                  )),
              const SizedBox(height: AppSpacing.md),
            ],
          );

    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          nowBlock,
          const _RecordMessage('아직 협회에 등록된 전적이 없습니다.'),
        ],
      );
    }

    final best = results.reduce((a, b) => b.points > a.points ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nowBlock,
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('최고의 순간', style: tt.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text('${best.tournamentName} ${best.resultLabel}', style: tt.titleMedium),
              Text('+${best.points}점', style: tt.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('전적 ${results.length}건', style: tt.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        ...results.map((r) => _ResultTile(result: r)),
        const SizedBox(height: AppSpacing.sm),
        Text('협회 공표 기준입니다. 앱이 계산한 점수가 아닙니다.', style: tt.bodySmall),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final PlayerResult result;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = result.playedOn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.tournamentName, style: tt.bodyLarge),
                Text(
                  '${d.year}.${d.month}.${d.day}'
                  '${result.eventRaw == null ? '' : ' · ${result.eventRaw}'}',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
          // 정규화 실패 행은 resultLabel 이 협회 원문을 그대로 돌려준다.
          Text(result.resultLabel, style: tt.bodyLarge),
          const SizedBox(width: AppSpacing.md),
          Text('+${result.points}', style: tt.bodyLarge),
        ],
      ),
    );
  }
}

class _RecordMessage extends StatelessWidget {
  const _RecordMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => AppCard(
        variant: AppCardVariant.outlined,
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _RecordSkeleton extends StatelessWidget {
  const _RecordSkeleton();

  @override
  Widget build(BuildContext context) => const AppCard(
        variant: AppCardVariant.outlined,
        child: SizedBox(height: 96),
      );
}
```

**주의**: `AppCard` · `SectionHeader` · `AppSpacing` 의 실제 경로와 생성자 인자는 `profile_records_widgets.dart` 상단 import 를 보고 맞춘다. 위 코드는 그 파일의 사용 패턴을 따른 것이다.

- [ ] **Step 5: 테스트를 통과시킨다**

```bash
cd app && flutter test test/widgets/my_record_section_test.dart
```

Expected: PASS

- [ ] **Step 6: 프로필에 붙인다**

`app/lib/screens/profile_screen.dart:400` 의 `const MyTournamentRecordsSection(),` 를 `const MyRecordSection(),` 으로 바꾸고 import 를 추가한다.

`MyTournamentRecordsSection` 은 **지우지 않는다** — 즐겨찾기 대회 목록으로서 다른 자리에서 쓸 수 있고, 이 작업의 범위는 "내 기록" 자리를 진짜 기록으로 바꾸는 것이다. 다만 이름이 내용과 어긋나므로 클래스 주석에 한 줄 남긴다:

```dart
/// 즐겨찾기한 대회 목록. (이름과 달리 성적 기록이 아니다 — 성적은 MyRecordSection)
```

- [ ] **Step 7: 전체 검사 후 커밋**

```bash
cd app && flutter analyze && flutter test
```

Expected: 전부 PASS

```bash
git add app/lib/widgets/profile/my_record_widgets.dart \
        app/lib/state/providers.dart \
        app/lib/screens/profile_screen.dart \
        app/lib/widgets/profile/profile_records_widgets.dart \
        app/test/widgets/my_record_section_test.dart
git commit -m "feat(app): 프로필 '내 기록' — 연결 유도 + 협회 전적

연결 전에는 무엇을 얻는지 먼저 말하고 랭킹 화면으로 보낸다. 연결 후에는
최고의 순간과 전적 타임라인을 보여준다. 순위 관련 블록은 스냅샷이 쌓인
뒤 2단계에서 붙인다 — 빈 그래프를 그리지 않는다."
```

---

## 마무리 — 배포와 확인

- [ ] **PR 을 올리고 CI 통과를 확인한다.** `gh pr create --base main`. admin 강제 머지 금지.
- [ ] **codex 리뷰를 받는다** (머지 전 필수). 프롬프트는 관심사별로 쪼갠다 — 광범위하면 탐색에 갇혀 무응답이 된다.
- [ ] **머지 후 `supabase db push`** — 마이그레이션 자동 배포가 없다.
- [ ] **Edge Function 배포** — `supabase functions deploy crawl-dispatch`. CI 가 배포하지 않는다.
- [ ] **배포 후 advisor 확인** — `get_advisors(type: security)`. 새 테이블·함수가 경고를 만들지 않았는지. 로컬 초록불이 프로덕션 권한을 보증하지 않는다.
- [ ] **첫 연결 승인 1건을 실제로 만들어 확인한다.** 승인 → 다음 크롤 → 전적이 채워지는지. 승인 0건이면 이 기능은 아무에게도 보이지 않는다.

## 이 계획이 스펙에서 의도적으로 미룬 것

**스펙 §6.2 의 "연결 승인 직후 1회" 수집을 넣지 않았다.** 승인 후 다음 크롤(매일 22:10)까지 최대 24시간 기다린다.

이유는 그 한 줄이 관리자 승인 경로에 Edge 호출을 끼워 넣는 작업이고, 승인 자체가 하루 몇 건 규모라 대기 24시간이 치명적이지 않기 때문이다. **승인 직후 즉시 채워지는 게 첫인상에 중요하다고 판단되면 별도 작업으로 올린다.**

빠뜨린 게 아니라 미룬 것이므로, 승인 화면에 "내일 반영됩니다" 안내를 넣을지는 구현 중 판단한다.

## 2단계 (별도 계획)

스냅샷이 2~3주 쌓인 뒤 착수한다.

- 라이프베스트(최고 순위·달성일), 순위 추이 꺾은선, 최근 변화(`▲5계단`)
- 시즌 구분 표시 (2027년 1월 협회 포인트 리셋 대비)
