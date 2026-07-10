# P3 tennis_org enum → text FK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `tennis_org` PG enum을 제거하고 협회 컬럼들이 `tennis_orgs` 표를 text FK로 참조하게 전환해, 신규 협회 추가가 DDL·앱배포 없이 INSERT 1줄로 가능해지도록 한다.

**Architecture:** enum을 참조하는 대상은 셋뿐 — `user_tennis_orgs.org`(스칼라), `tennis_tournament_details.host_orgs`(배열), 함수 `tournaments_for_user`(반환+캐스트). 단일 마이그레이션에서 컬럼 2개를 text로 전환하고, 함수를 재생성(반환 tennis_org[]→text[], 캐스트 제거)한 뒤, 미참조가 된 enum 타입을 드롭한다. enum 라벨=`tennis_orgs.code`라 값 보존·앱 투명.

**Tech Stack:** Supabase Postgres. 마이그레이션은 `execute_sql`로 직접 적용(`db push` 금지). 프로젝트 ref `bsjdgwmveokanclqwtvx`.

## Global Constraints

- **`db push` 금지** — 히스토리 붕괴(JY-116). `execute_sql`/`apply_migration`으로 직접 적용, `.sql` 파일은 기록용 커밋.
- **함수 DROP/CREATE 후** 반드시 `NOTIFY pgrst, 'reload schema'`. overload 주의(DROP 시 정확한 13-인자 시그니처 지정).
- **앱/TS 변경 없음** — org는 문자열 그대로. `isValidTennisOrg` 하드코딩은 P3 범위 밖.
- **결정**: enum 타입 드롭 O / host_orgs[] 원소검증 트리거 X / 스칼라 `user_tennis_orgs.org`에 FK O.
- **`futsal_org` enum은 건드리지 않는다** — `tournaments_for_user` 반환의 `host_futsal_orgs futsal_org[]`는 그대로 유지.
- **셀프 머지**: CI 통과 + 리뷰 후 정상 머지 OK(2026-07-10 갱신). `--admin` 금지.

---

### Task 1: enum → text 전환 마이그레이션 086

**Files:**
- Create: `supabase/migrations/086_tennis_org_enum_to_text.sql`

**Interfaces:**
- Consumes: `public.tennis_orgs(code)`(P1 시드, 10행), 기존 enum `public.tennis_org`, 함수 `public.tournaments_for_user(uuid,text,text,date,date,boolean,text,integer,integer,text,text,text[],text)`.
- Produces:
  - `user_tennis_orgs.org` : `text` + FK `user_tennis_orgs_org_fkey → tennis_orgs(code)`.
  - `tennis_tournament_details.host_orgs` : `text[]` (default `'{}'::text[]`).
  - `tournaments_for_user(...)` : 반환 `host_orgs text[]`(그 외 시그니처·행동 불변).
  - enum `public.tennis_org` : 제거됨.

- [ ] **Step 1: 전환 전 스냅샷 캡처 (검증 기준선)**

`execute_sql`로 실행하고 결과 보관:

```sql
-- (a) 컬럼 데이터 스냅샷
select 'uto_org' as k, org::text as v, count(*) from user_tennis_orgs group by org::text
union all
select 'ttd_hostorgs', array_to_string(host_orgs::text[], ','), count(*)
from tennis_tournament_details group by host_orgs::text
order by 1,2;

-- (b) 대표 유저별 tournaments_for_user host_orgs 포함 결과
--   각 distinct user_id 에 대해:
--   select array_agg(id order by id) as ids,
--          array_agg(distinct array_to_string(host_orgs,',')) as horgs
--   from tournaments_for_user('<uid>'::uuid, 'tennis', null,null,null, true);

-- (c) host_org 필터 동작 기준선 (host_orgs에 실제 존재하는 값 하나로)
select distinct unnest(host_orgs)::text as org from tennis_tournament_details limit 5;
```

기대: 스냅샷 기록. 이후 diff=0 판정 기준.

- [ ] **Step 2: 마이그레이션 SQL 파일 작성**

`supabase/migrations/086_tennis_org_enum_to_text.sql`:

```sql
-- 086: P3 전국확장 — tennis_org enum 탈출(enum → text FK).
--   enum 참조 3곳: user_tennis_orgs.org, tennis_tournament_details.host_orgs[],
--   함수 tournaments_for_user(반환+캐스트). 값 보존(라벨=tennis_orgs.code), 앱 투명.
--   비파괴 컬럼전환 → 함수재생성 → 타입드롭 순.

-- 1) user_tennis_orgs.org : enum → text + FK
alter table public.user_tennis_orgs
  alter column org type text using org::text;
alter table public.user_tennis_orgs
  add constraint user_tennis_orgs_org_fkey
  foreign key (org) references public.tennis_orgs(code);

-- 2) tennis_tournament_details.host_orgs : tennis_org[] → text[]
alter table public.tennis_tournament_details
  alter column host_orgs drop default;
alter table public.tennis_tournament_details
  alter column host_orgs type text[] using host_orgs::text[];
alter table public.tennis_tournament_details
  alter column host_orgs set default '{}'::text[];

-- 3) tournaments_for_user 재생성 (반환 host_orgs text[], p_host_org 캐스트 제거)
--    반환 타입 변경이라 CREATE OR REPLACE 불가 → DROP 후 CREATE.
drop function if exists public.tournaments_for_user(uuid,text,text,date,date,boolean,text,integer,integer,text,text,text[],text);

create function public.tournaments_for_user(
  p_user_id uuid, p_sport text default null, p_region text default null,
  p_date_from date default null, p_date_to date default null,
  p_only_my_grade boolean default true, p_query text default null,
  p_limit integer default 50, p_offset integer default 0,
  p_region_code text default null, p_host_org text default null,
  p_division_codes text[] default null, p_recruiting text default null
)
returns table(
  id uuid, sport text, title text, organizer text, description text,
  start_date date, end_date date, application_deadline date, region text,
  region_code text, host_associations text[], location text, eligible_grades text[],
  division_label_local text, entry_fee integer, entry_fee_unit text, prize text,
  format text, source_url text, status text, created_at timestamptz,
  host_orgs text[], division_kta_standard text, division_gender text,
  division_age_group text, is_joint_event boolean, host_futsal_orgs futsal_org[],
  t_venue_type text, t_surface_type text, t_match_format text, t_player_count integer,
  t_team_count_max integer, t_roster_min integer, t_roster_max integer,
  futsal_event_category text
)
language sql stable
set search_path to 'public'
as $function$
  SELECT
    t.id, t.sport::text, t.title, t.organizer, t.description, t.start_date,
    t.end_date, t.application_deadline, t.region, t.region_code, t.host_associations,
    t.location, t.eligible_grades, t.division_label_local, t.entry_fee, t.entry_fee_unit,
    t.prize, t.format, t.source_url, t.status::text, t.created_at,
    tt.host_orgs, tt.division_kta_standard, tt.division_gender, tt.division_age_group,
    tt.is_joint_event, ft.host_futsal_orgs, ft.venue_type, ft.surface_type,
    ft.match_format, ft.player_count, ft.team_count_max, ft.roster_min, ft.roster_max,
    ft.event_category
  FROM public.tournaments t
  LEFT JOIN public.tennis_tournament_details tt ON tt.tournament_id = t.id
  LEFT JOIN public.futsal_tournament_details ft ON ft.tournament_id = t.id
  WHERE t.status = 'published'
    AND (p_sport IS NULL OR t.sport::text = p_sport)
    AND (p_region IS NULL OR t.region = p_region)
    AND (p_region_code IS NULL OR t.region_code = p_region_code)
    AND (p_date_from IS NULL OR coalesce(t.end_date, t.start_date) >= p_date_from)
    AND (p_date_to IS NULL OR t.start_date <= p_date_to)
    AND (p_host_org IS NULL OR tt.host_orgs @> ARRAY[p_host_org])
    AND (p_division_codes IS NULL OR p_division_codes && t.eligible_grades)
    AND (
      p_recruiting IS NULL
      OR (p_recruiting = 'open' AND (t.application_deadline IS NULL OR t.application_deadline >= current_date))
      OR (p_recruiting = 'closed' AND t.application_deadline IS NOT NULL AND t.application_deadline < current_date)
    )
    AND (
      p_query IS NULL
      OR t.title ILIKE '%' || p_query || '%'
      OR COALESCE(t.organizer, '') ILIKE '%' || p_query || '%'
      OR COALESCE(t.description, '') ILIKE '%' || p_query || '%'
    )
    AND (
      NOT p_only_my_grade
      OR (
        (t.sport = 'tennis' AND EXISTS (
          SELECT 1 FROM public.user_tennis_orgs uto
          WHERE uto.user_id = p_user_id
            AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades
        ))
        OR
        (t.sport = 'futsal' AND EXISTS (
          SELECT 1 FROM public.user_sports us
          WHERE us.user_id = p_user_id AND us.sport = t.sport AND us.grade = ANY(t.eligible_grades)
        ))
      )
    )
  ORDER BY t.start_date ASC, t.created_at DESC
  LIMIT GREATEST(p_limit, 0) OFFSET GREATEST(p_offset, 0);
$function$;

-- 4) 미참조가 된 enum 타입 제거
drop type public.tennis_org;

notify pgrst, 'reload schema';
```

- [ ] **Step 3: 마이그레이션 적용**

`execute_sql`로 위 파일 내용 전체를 하나의 배치로 실행(`db push` 금지). 트랜잭션으로 감싸 4단계가 원자적으로 적용되게 한다.

기대: 에러 없이 완료. 특히 `add constraint ... foreign key`가 실패하지 않아야 함(기존 org 값 전부 tennis_orgs.code에 존재 → enum이 애초에 10라벨만 허용했고 P1이 10개 다 code로 시드했으므로 보장).

- [ ] **Step 4: 구조 검증 단언**

`execute_sql`:

```sql
select
  -- 컬럼 타입 전환 확인
  (select data_type from information_schema.columns
     where table_name='user_tennis_orgs' and column_name='org') = 'text'      as uto_org_text,
  (select udt_name from information_schema.columns
     where table_name='tennis_tournament_details' and column_name='host_orgs') = '_text' as hostorgs_text,
  -- FK 존재 확인
  exists(select 1 from pg_constraint where conname='user_tennis_orgs_org_fkey') as fk_ok,
  -- enum 제거 확인
  (select count(*) from pg_type where typname='tennis_org') = 0                as enum_gone,
  -- 함수 반환 host_orgs가 text[]인지(정의에 tennis_org[] 잔존 없음)
  (select pg_get_functiondef(oid) not ilike '%tennis_org%'
     from pg_proc where proname='tournaments_for_user' and prokind='f')       as fn_clean;
```

기대: 다섯 컬럼 모두 `true`.

- [ ] **Step 5: 데이터·RPC 동등 검증 (diff=0)**

Step 1의 (a)(b)(c) 쿼리를 재실행해 Step 1 결과와 비교.

기대:
- (a) 컬럼 데이터 스냅샷 전후 동일(값·행수).
- (b) 각 유저 `tournaments_for_user` 결과 id 집합 + host_orgs 내용 전후 **완전 동일(diff=0)**.
- (c) host_orgs에 존재하는 org 값으로 `tournaments_for_user(..., p_host_org := '<org>')` 호출 시 해당 대회가 정상 필터링됨(전환 전 동일 호출과 결과 동일).

diff가 있으면 롤백 검토(마이그레이션은 트랜잭션이라 실패 시 자동 롤백; 적용 후 문제 발견 시 역마이그레이션 필요 — enum 재생성 비용 큼이므로 Step 4·5 게이트를 반드시 통과 확인 후에만 커밋).

- [ ] **Step 6: 커밋**

```bash
git add supabase/migrations/086_tennis_org_enum_to_text.sql
git commit -m "feat(db): P3 전국확장 — tennis_org enum → text FK

- user_tennis_orgs.org: enum→text + FK(tennis_orgs.code)
- tennis_tournament_details.host_orgs: tennis_org[]→text[]
- tournaments_for_user 재생성(반환 host_orgs text[], 캐스트 제거)
- enum tennis_org 드롭. 값 보존·앱 투명. futsal_org enum은 유지
- 검증: 구조 단언 5개 + 데이터/RPC diff=0

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- user_tennis_orgs.org → text + FK → Step 2 (1) ✓
- host_orgs → text[] + default → Step 2 (2) ✓
- tournaments_for_user 재생성(반환 text[], 캐스트 제거) → Step 2 (3) ✓
- enum 드롭 → Step 2 (4) ✓
- NOTIFY pgrst → Step 2 ✓
- 결정 ①(드롭) ②(트리거 없음, 스칼라 FK) → 반영 ✓
- futsal_org 미변경 → 반환 시그니처에 `host_futsal_orgs futsal_org[]` 유지 ✓
- 성공기준 1(데이터 보존) → Step 1+5(a) ✓
- 성공기준 2(FK 무결성) → Step 3+4(fk_ok) ✓
- 성공기준 3(RPC 동등) → Step 5(b) ✓
- 성공기준 4(필터 동작) → Step 5(c) ✓
- 성공기준 5(enum 제거) → Step 4(enum_gone) ✓
- 범위 밖(isValidTennisOrg, 트리거, 신규협회) → 계획 미포함 ✓

**2. Placeholder scan:** 없음. 모든 SQL·명령·기대값 명시.

**3. Type consistency:** `p_host_org text`(불변), 반환 `host_orgs text[]`, FK 이름 `user_tennis_orgs_org_fkey` — 전 스텝 일관.

TDD 노트: DB 마이그레이션이라 Step 1 사전 스냅샷이 회귀 기준선, Step 4(구조)·5(데이터/RPC)가 검증 게이트. 함수 재생성은 값 보존이 목표라 diff=0이 곧 통과 조건.
