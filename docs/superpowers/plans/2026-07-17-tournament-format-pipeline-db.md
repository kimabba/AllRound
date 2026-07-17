# 대회 요강 정형화 파이프라인 — Plan 1: DB 마이그레이션·RPC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `tournaments`에 정형화 상태 컬럼을 추가하고, format-pending worker가 쓸 durable claim/complete/reject/fail RPC와 임베딩 경합 방지 트리거·format_* 변조 차단 트리거를 만든다.

**Architecture:** 단일 마이그레이션 파일(`apply_migration`)로 컬럼→인덱스→트리거→RPC→GRANT→백필→`NOTIFY pgrst`를 순서대로 적용. RPC는 `processing`+`claim_token` lease 상태머신으로 중복 처리를 막고, complete는 token·문서·content_hash 조건으로 stale-write를 차단한다. 검증은 원격 DB에 `execute_sql` 시나리오 쿼리로 수행한다.

**Tech Stack:** Postgres(Supabase), pl/pgSQL, Supabase MCP(`apply_migration`/`execute_sql`), Deno(모델 타입).

## Global Constraints

- `supabase db push` 금지(JY-116). 원격 적용은 `apply_migration`(히스토리 기록), repo에 동일 SQL 파일 커밋.
- 스키마/RPC 변경 마지막에 `NOTIFY pgrst, 'reload schema'` 필수.
- 신규 컬럼/RPC는 RLS·권한 검토 필수(서버/DB가 진실 원천).
- TypeScript `any` / Dart `dynamic` 금지. `format_status`는 union/enum 타입.
- 마이그레이션 파일명: `supabase/migrations/YYYYMMDDHHMMSS_<name>.sql` (예: `20260717HHMMSS_tournament_format_pipeline.sql`).
- 콘텐츠 컬럼(`regulation_*`/`prize`/`format`/`description`)은 롤백해도 보존(불변).
- `format_status` 값: `pending, processing, formatted, needs_review, failed, skipped`.

---

### Task 1: 마이그레이션 파일 스캐폴드 + 컬럼·CHECK 추가

**Files:**
- Create: `supabase/migrations/20260717HHMMSS_tournament_format_pipeline.sql` (실제 실행 시각으로 타임스탬프 확정)

**Interfaces:**
- Produces: `tournaments`에 컬럼 `format_status text`, `format_attempts smallint`, `format_claim_token uuid`, `claimed_at timestamptz`, `format_document_id uuid`, `format_source_hash text`, `format_model text`, `formatted_at timestamptz`, `format_flags jsonb`, `format_staged jsonb`, `embedding_input_revision bigint`.

- [ ] **Step 1: 마이그레이션 파일에 컬럼 추가 SQL 작성**

파일 상단에 헤더 주석 + 컬럼 블록:

```sql
-- 대회 요강 AI 정형화 파이프라인: 상태 컬럼 + lease + RPC + 트리거.
-- 설계: docs/superpowers/specs/2026-07-17-tournament-regulation-ai-formatting-design.md
-- 적용: apply_migration (db push 금지). 마지막에 NOTIFY pgrst.

alter table public.tournaments
  add column if not exists format_status text not null default 'pending'
    constraint tournaments_format_status_check
    check (format_status in ('pending','processing','formatted','needs_review','failed','skipped')),
  add column if not exists format_attempts smallint not null default 0
    constraint tournaments_format_attempts_check check (format_attempts >= 0),
  add column if not exists format_claim_token uuid,
  add column if not exists claimed_at timestamptz,
  add column if not exists format_document_id uuid,
  add column if not exists format_source_hash text,
  add column if not exists format_model text,
  add column if not exists formatted_at timestamptz,
  add column if not exists format_flags jsonb
    constraint tournaments_format_flags_check
    check (format_flags is null or jsonb_typeof(format_flags) = 'array'),
  add column if not exists format_staged jsonb
    constraint tournaments_format_staged_check
    check (format_staged is null or jsonb_typeof(format_staged) = 'object'),
  add column if not exists embedding_input_revision bigint not null default 0
    constraint tournaments_embedding_input_revision_check check (embedding_input_revision >= 0);
```

- [ ] **Step 2: 컬럼 블록만 원격 적용해 검증 (apply_migration은 Task 8에서 전체 일괄, 여기선 execute_sql로 선검증)**

Run (`execute_sql`, 위 alter 블록):
Expected: 성공. 이어서 확인 쿼리 —

```sql
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name='tournaments'
  and (column_name like 'format%' or column_name in ('claimed_at','embedding_input_revision'))
order by column_name;
```
Expected: 11개 컬럼 존재, `format_status` default `'pending'` not null, `format_attempts`/`embedding_input_revision` default 0 not null.

- [ ] **Step 3: CHECK 제약 검증**

Run (`execute_sql`):
```sql
select conname from pg_constraint
where conrelid='public.tournaments'::regclass
  and conname in ('tournaments_format_status_check','tournaments_format_attempts_check',
                  'tournaments_format_flags_check','tournaments_format_staged_check',
                  'tournaments_embedding_input_revision_check')
order by conname;
```
Expected: 5개 제약 모두 존재.

- [ ] **Step 4: 위반값 거부 확인**

Run (`execute_sql`):
```sql
do $$ begin
  begin
    update public.tournaments set format_status='bogus' where id=(select id from public.tournaments limit 1);
    raise exception 'CHECK not enforced';
  exception when check_violation then null; end;
end $$;
```
Expected: 오류 없이 완료(= CHECK가 bogus를 막고 check_violation을 삼킴).

---

### Task 2: 선별용 partial index

**Files:**
- Modify: 같은 마이그레이션 파일에 index 블록 추가.

**Interfaces:**
- Produces: `tournaments_format_pending_idx` (partial, `where format_status='pending'`).

- [ ] **Step 1: index SQL 작성 + 적용**

```sql
create index if not exists tournaments_format_pending_idx
  on public.tournaments (created_at)
  where format_status = 'pending';
```
Run (`execute_sql`).

- [ ] **Step 2: 검증**

Run (`execute_sql`):
```sql
select indexname, indexdef from pg_indexes
where tablename='tournaments' and indexname='tournaments_format_pending_idx';
```
Expected: 1행, indexdef에 `WHERE (format_status = 'pending'::text)` 포함.

---

### Task 3: 트리거 — 임베딩 revision + format_* 변조 차단

**Files:**
- Modify: 마이그레이션 파일에 트리거 함수 2개.

**Interfaces:**
- Consumes: 기존 트리거 함수 `public.invalidate_tournament_embedding()`(BEFORE UPDATE), `public.is_admin()`.
- Produces: revision 증가 로직, 신규 트리거 `tournaments_guard_format_columns`.

- [ ] **Step 1: invalidate 트리거에 revision 증가 추가 (기존 함수 CREATE OR REPLACE, 기존 로직 보존 + 3줄 추가)**

```sql
create or replace function public.invalidate_tournament_embedding()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if (old.title is distinct from new.title)
     or (old.description is distinct from new.description)
     or (old.region is distinct from new.region)
     or (old.format is distinct from new.format)
     or (old.organizer is distinct from new.organizer)
     or (old.regulation_fields is distinct from new.regulation_fields)
     or (old.regulation_notes is distinct from new.regulation_notes)
     or (old.regulation_body is distinct from new.regulation_body)
  then
    new.embedding := null;
    new.embedding_updated_at := null;
    new.embedding_input_revision := old.embedding_input_revision + 1;  -- 신규: 경합 방지 (Plan1)
  end if;
  return new;
end;
$function$;
```

- [ ] **Step 2: format_* 변조 차단 트리거 함수 + 트리거 생성**

비-service·비-admin 세션이 `format_*`/`embedding_input_revision`을 바꾸면 거부(Codex P1: draft 소유자 위조 차단).

```sql
create or replace function public.guard_tournament_format_columns()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_admin() then
    if (new.format_status is distinct from old.format_status)
       or (new.format_attempts is distinct from old.format_attempts)
       or (new.format_claim_token is distinct from old.format_claim_token)
       or (new.claimed_at is distinct from old.claimed_at)
       or (new.format_document_id is distinct from old.format_document_id)
       or (new.format_source_hash is distinct from old.format_source_hash)
       or (new.format_model is distinct from old.format_model)
       or (new.formatted_at is distinct from old.formatted_at)
       or (new.format_flags is distinct from old.format_flags)
       or (new.format_staged is distinct from old.format_staged)
       or (new.embedding_input_revision is distinct from old.embedding_input_revision)
    then
      raise exception 'format_* columns are managed by the formatting pipeline';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tournaments_guard_format_columns on public.tournaments;
create trigger tournaments_guard_format_columns
  before update on public.tournaments
  for each row execute function public.guard_tournament_format_columns();
```
Run (`execute_sql`, 두 함수 + 트리거).

- [ ] **Step 3: revision 증가 검증**

Run (`execute_sql`):
```sql
with pick as (select id, embedding_input_revision r from public.tournaments limit 1)
update public.tournaments t set description = coalesce(t.description,'') || ' '
from pick where t.id=pick.id
returning t.embedding_input_revision - pick.r as delta;
```
Expected: `delta = 1`.

- [ ] **Step 4: 변조 차단 검증(관리자/서비스 세션에선 통과, 그 외 거부) — 서비스 컨텍스트 확인만**

Run (`execute_sql`, service 컨텍스트라 통과해야 함):
```sql
update public.tournaments set format_status = format_status
where id = (select id from public.tournaments limit 1);
```
Expected: 성공(=service/admin은 트리거에 막히지 않음). 일반 유저 거부는 Plan 5의 앱 통합 테스트에서 검증(주석으로 명시).

---

### Task 4: claim RPC (durable lease)

**Files:**
- Modify: 마이그레이션 파일에 `format_pending_claim`.

**Interfaces:**
- Produces: `public.format_pending_claim(p_batch_size int, p_lease_minutes int) returns table(tournament_id uuid, title text, sport public.sport, source text, claim_token uuid, document_id uuid, content_hash text, status public.tournament_status, formatted_at timestamptz)`. (status/formatted_at는 Plan 3의 스테이징 판정에 사용.)

- [ ] **Step 1: claim RPC 작성 + 적용**

```sql
create or replace function public.format_pending_claim(
  p_batch_size int default 4,
  p_lease_minutes int default 15
) returns table (
  tournament_id uuid, title text, sport public.sport, source text,
  claim_token uuid, document_id uuid, content_hash text,
  status public.tournament_status, formatted_at timestamptz
) language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  -- (1) 만료 lease 회수: processing인데 claimed_at 초과 → attempts에 따라 pending/failed
  update public.tournaments t
     set format_status = case when t.format_attempts >= 3 then 'failed' else 'pending' end,
         format_claim_token = null, claimed_at = null
   where t.format_status = 'processing'
     and t.claimed_at < now() - make_interval(mins => p_lease_minutes);

  -- (2) pending 클레임 → processing 원자 전이
  return query
  with claimed as (
    select t.id
    from public.tournaments t
    where t.format_status = 'pending'
      and t.manual_description = false
      and t.status <> 'draft'
      and t.format_attempts < 3
      and exists (select 1 from public.crawl_documents cd where cd.tournament_id = t.id)
    order by t.created_at
    limit p_batch_size
    for update of t skip locked
  ),
  latest_doc as (
    select c.id as tid, d.id as doc_id, d.content_hash as chash
    from claimed c
    join lateral (
      select cd.id, cd.content_hash
      from public.crawl_documents cd
      where cd.tournament_id = c.id
      order by cd.fetched_at desc, cd.id desc
      limit 1
    ) d on true
  ),
  stamped as (
    update public.tournaments t
       set format_status = 'processing',
           format_attempts = t.format_attempts + 1,
           format_claim_token = gen_random_uuid(),
           claimed_at = now(),
           format_document_id = ld.doc_id
      from latest_doc ld
     where t.id = ld.tid
    returning t.id, t.title, t.sport, t.source, t.format_claim_token, t.format_document_id,
              t.status, t.formatted_at
  )
  select s.id, s.title, s.sport, s.source, s.format_claim_token, s.format_document_id, ld.chash,
         s.status, s.formatted_at
  from stamped s join latest_doc ld on ld.tid = s.id;
end;
$$;
```
Run (`execute_sql`).

- [ ] **Step 2: 클레임 원자성·비중복 검증**

Run (`execute_sql`):
```sql
-- 백필 전이므로 pending이 존재. 2건 클레임 → processing 전이 + token 발급 확인.
select tournament_id, claim_token is not null tok, document_id is not null doc, content_hash is not null ch
from public.format_pending_claim(2, 15);
```
Expected: 최대 2행, tok/doc/ch 모두 true.

- [ ] **Step 3: 재클레임이 같은 행을 다시 잡지 않음(중복 방지) 검증**

Run (`execute_sql`):
```sql
-- 방금 processing된 행은 다음 claim에서 제외되어야 한다.
select count(*) processing_now from public.tournaments where format_status='processing';
select count(*) as reclaimed from public.format_pending_claim(50, 15);  -- processing 제외됨
```
Expected: `reclaimed`가 남은 pending 수만큼이고, 이미 processing된 행은 미포함(중복 0).

- [ ] **Step 4: 테스트 상태 원복**

Run (`execute_sql`):
```sql
update public.tournaments
   set format_status='pending', format_attempts=0, format_claim_token=null,
       claimed_at=null, format_document_id=null
 where format_status='processing';
```
Expected: 성공(다음 백필 Task 전에 깨끗한 상태). ※ 실제 worker 가동 전이므로 attempts 리셋 안전.

---

### Task 5: complete / reject / fail RPC

**Files:**
- Modify: 마이그레이션 파일에 3개 RPC.

**Interfaces:**
- Consumes: claim이 발급한 `claim_token`, `document_id`, `content_hash`.
- Produces:
  - `format_pending_complete(p_tid uuid, p_token uuid, p_document_id uuid, p_source_hash text, p_regulation_fields jsonb, p_regulation_notes text[], p_regulation_body text, p_prize text, p_format text, p_description text, p_model text, p_flags jsonb, p_stage boolean) returns boolean`
  - `format_pending_reject(p_tid uuid, p_token uuid, p_flags jsonb, p_source_hash text) returns boolean`
  - `format_pending_fail(p_tid uuid, p_token uuid) returns void`

- [ ] **Step 1: complete RPC 작성 + 적용**

```sql
create or replace function public.format_pending_complete(
  p_tid uuid, p_token uuid, p_document_id uuid, p_source_hash text,
  p_regulation_fields jsonb, p_regulation_notes text[], p_regulation_body text,
  p_prize text, p_format text, p_description text,
  p_model text, p_flags jsonb, p_stage boolean
) returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_rows int;
begin
  -- stale-write 가드: 문서·해시가 여전히 최신이 아니면 재큐하고 반영 안 함.
  if not exists (
    select 1 from public.crawl_documents cd
    where cd.id = p_document_id and cd.tournament_id = p_tid and cd.content_hash = p_source_hash
  ) then
    update public.tournaments
       set format_status='pending', format_claim_token=null, claimed_at=null
     where id = p_tid and format_claim_token = p_token and format_status='processing';
    return false;
  end if;

  if p_stage then
    -- 기존 published 검수 스테이징: 콘텐츠 미기록, staged에 보관, needs_review.
    update public.tournaments t set
      format_status = 'needs_review',
      format_staged = jsonb_build_object(
        'regulation_fields', coalesce(p_regulation_fields,'[]'::jsonb),
        'regulation_notes', to_jsonb(coalesce(p_regulation_notes, array[]::text[])),
        'regulation_body', p_regulation_body, 'prize', p_prize,
        'format', p_format, 'description', p_description),
      format_model = p_model, format_flags = p_flags,
      format_source_hash = p_source_hash, format_claim_token = null, claimed_at = null
    where t.id = p_tid and t.format_claim_token = p_token
      and t.format_status = 'processing' and t.manual_description = false;
  else
    -- 신규/승인 유입: 콘텐츠 직접 반영, formatted.
    update public.tournaments t set
      regulation_fields = p_regulation_fields, regulation_notes = p_regulation_notes,
      regulation_body = p_regulation_body, prize = p_prize, format = p_format,
      description = p_description, format_status = 'formatted', formatted_at = now(),
      format_model = p_model, format_flags = p_flags, format_source_hash = p_source_hash,
      format_staged = null, format_claim_token = null, claimed_at = null
    where t.id = p_tid and t.format_claim_token = p_token
      and t.format_status = 'processing' and t.manual_description = false;
  end if;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;
```

- [ ] **Step 2: reject·fail RPC 작성 + 적용**

```sql
create or replace function public.format_pending_reject(
  p_tid uuid, p_token uuid, p_flags jsonb, p_source_hash text
) returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_rows int;
begin
  update public.tournaments t set
    format_status = 'needs_review', format_flags = p_flags,
    format_source_hash = p_source_hash, format_claim_token = null, claimed_at = null
  where t.id = p_tid and t.format_claim_token = p_token and t.format_status = 'processing';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

create or replace function public.format_pending_fail(
  p_tid uuid, p_token uuid
) returns void language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  update public.tournaments t
     set format_status = case when t.format_attempts >= 3 then 'failed' else 'pending' end,
         format_claim_token = null, claimed_at = null
   where t.id = p_tid and t.format_claim_token = p_token and t.format_status = 'processing';
end;
$$;
```
Run (`execute_sql`, Step1+Step2).

- [ ] **Step 3: 시나리오 검증 (claim→complete 성공, 잘못된 token no-op, stale reject)**

Run (`execute_sql`):
```sql
do $$
declare c record; v_ok boolean; v_hash text;
begin
  -- 클레임 1건
  select * into c from public.format_pending_claim(1, 15) limit 1;
  -- (a) 틀린 token → false
  v_ok := public.format_pending_complete(c.tournament_id, gen_random_uuid(), c.document_id,
            c.content_hash, '[]'::jsonb, array[]::text[], null, null, null, '요약',
            'test', null, false);
  assert v_ok = false, 'wrong token must no-op';
  -- (b) 올바른 token + stage=false → formatted
  v_ok := public.format_pending_complete(c.tournament_id, c.claim_token, c.document_id,
            c.content_hash, '[{"label":"참가비","value":"64000"}]'::jsonb, array['보험가입']::text[],
            '본문', '상금', '개인복식', '요약', 'test', null, false);
  assert v_ok = true, 'valid complete must apply';
  perform 1 from public.tournaments where id=c.tournament_id and format_status='formatted';
  assert found, 'status must be formatted';
  -- 원복
  update public.tournaments set format_status='pending', format_attempts=0,
    regulation_fields=null, regulation_notes=null, regulation_body=null,
    prize=null, format=null, format_source_hash=null, formatted_at=null, format_model=null
   where id=c.tournament_id;
  raise notice 'scenario ok';
end $$;
```
Expected: `NOTICE: scenario ok`, 오류 없음.

- [ ] **Step 4: stale reject 검증**

Run (`execute_sql`):
```sql
do $$
declare c record; v_ok boolean;
begin
  select * into c from public.format_pending_claim(1, 15) limit 1;
  -- 원문 해시가 바뀐 상황 모사: 잘못된 source_hash로 complete → false + 재큐(pending)
  v_ok := public.format_pending_complete(c.tournament_id, c.claim_token, c.document_id,
            'STALEHASH', '[]'::jsonb, array[]::text[], null, null, null, 'x', 'test', null, false);
  assert v_ok = false, 'stale hash must not apply';
  perform 1 from public.tournaments where id=c.tournament_id and format_status='pending';
  assert found, 'stale must requeue to pending';
  update public.tournaments set format_attempts=0 where id=c.tournament_id;
end $$;
```
Expected: 오류 없음(assert 통과).

---

### Task 6: 권한 (REVOKE + service_role GRANT)

**Files:**
- Modify: 마이그레이션 파일에 GRANT/REVOKE.

**Interfaces:**
- Produces: 4개 RPC 실행 권한이 `service_role`에만.

- [ ] **Step 1: REVOKE/GRANT 작성 + 적용 (Codex P0-4: service_role 명시 GRANT)**

```sql
revoke execute on function public.format_pending_claim(int,int)   from public, anon, authenticated;
revoke execute on function public.format_pending_complete(uuid,uuid,uuid,text,jsonb,text[],text,text,text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke execute on function public.format_pending_reject(uuid,uuid,jsonb,text)  from public, anon, authenticated;
revoke execute on function public.format_pending_fail(uuid,uuid)   from public, anon, authenticated;

grant execute on function public.format_pending_claim(int,int)   to service_role;
grant execute on function public.format_pending_complete(uuid,uuid,uuid,text,jsonb,text[],text,text,text,text,text,jsonb,boolean) to service_role;
grant execute on function public.format_pending_reject(uuid,uuid,jsonb,text)  to service_role;
grant execute on function public.format_pending_fail(uuid,uuid)   to service_role;
```
Run (`execute_sql`).

- [ ] **Step 2: 권한 검증**

Run (`execute_sql`):
```sql
select p.proname,
  has_function_privilege('service_role', p.oid, 'execute') svc,
  has_function_privilege('anon', p.oid, 'execute') anon,
  has_function_privilege('authenticated', p.oid, 'execute') auth
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname like 'format_pending_%'
order by p.proname;
```
Expected: 모든 행 `svc=true, anon=false, auth=false`.

---

### Task 7: 백필 (검증 가드 → skipped 31 / pending 50)

**Files:**
- Modify: 마이그레이션 파일에 백필 UPDATE.

- [ ] **Step 1: 적용 직전 기대값 재검증(Codex P2)**

Run (`execute_sql`):
```sql
select
  count(*) filter (where manual_description or not exists
    (select 1 from public.crawl_documents cd where cd.tournament_id=t.id)) as expect_skipped,
  count(*) filter (where not manual_description and exists
    (select 1 from public.crawl_documents cd where cd.tournament_id=t.id)) as expect_pending
from public.tournaments t;
```
Expected: `expect_skipped=31, expect_pending=50`. **다르면 중단하고 데이터 재확인.**

- [ ] **Step 2: 백필 UPDATE 작성 + 적용**

```sql
update public.tournaments t
   set format_status = 'skipped'
 where t.format_status = 'pending'
   and ( t.manual_description = true
      or not exists (select 1 from public.crawl_documents cd where cd.tournament_id = t.id) );
```
Run (`execute_sql`).

- [ ] **Step 3: 결과 검증**

Run (`execute_sql`):
```sql
select format_status, count(*) from public.tournaments group by 1 order by 1;
```
Expected: `pending=50, skipped=31` (formatted/processing/needs_review/failed 0).

---

### Task 8: 마이그레이션 파일 통합 커밋 + NOTIFY + 타입 재생성

**Files:**
- Modify: `supabase/migrations/20260717HHMMSS_tournament_format_pipeline.sql` (Task 1~7 블록 순서대로 + NOTIFY + 롤백 주석)
- Modify: Dart 모델(`app/lib/models/tournament.dart`)에 `formatStatus` union — **표시 무관 필드는 Plan 5에서 통합**, 여기선 타입 재생성만.

- [ ] **Step 1: 파일 끝에 NOTIFY + 롤백 주석 추가**

```sql
notify pgrst, 'reload schema';

-- ── 롤백 (역순, 콘텐츠 컬럼 불변) ──────────────────────────────
-- drop function if exists public.format_pending_fail(uuid,uuid);
-- drop function if exists public.format_pending_reject(uuid,uuid,jsonb,text);
-- drop function if exists public.format_pending_complete(uuid,uuid,uuid,text,jsonb,text[],text,text,text,text,text,jsonb,boolean);
-- drop function if exists public.format_pending_claim(int,int);
-- drop trigger if exists tournaments_guard_format_columns on public.tournaments;
-- drop function if exists public.guard_tournament_format_columns();
-- -- invalidate_tournament_embedding 은 revision 3줄만 제거해 원복(위 정의 참고).
-- drop index if exists public.tournaments_format_pending_idx;
-- alter table public.tournaments
--   drop column if exists format_status, drop column if exists format_attempts,
--   drop column if exists format_claim_token, drop column if exists claimed_at,
--   drop column if exists format_document_id, drop column if exists format_source_hash,
--   drop column if exists format_model, drop column if exists formatted_at,
--   drop column if exists format_flags, drop column if exists format_staged,
--   drop column if exists embedding_input_revision;
-- notify pgrst, 'reload schema';
```

- [ ] **Step 2: `apply_migration`으로 전체 파일을 히스토리에 기록**

Run: Supabase MCP `apply_migration`, name=`tournament_format_pipeline`, query=파일 전문.
Expected: 성공. (선검증에서 이미 `create or replace`/`if not exists`/idempotent 백필이라 재적용 안전.)
Note: apply 도구의 트랜잭션 보장이 불확실하면(Codex P1) 파일을 `begin; ... commit;`로 감싸고 재적용.

- [ ] **Step 3: PostgREST 캐시·신규 컬럼 REST 노출 확인**

Run (`execute_sql`):
```sql
select id, format_status from public.tournaments limit 1;
```
Expected: 성공. 이후 `list_migrations`로 마이그레이션 기록 확인.

- [ ] **Step 4: Dart 타입 재생성 (any/dynamic 금지)**

Run:
```bash
cd /Users/ssfak/Documents/01-github/AllRound
supabase gen types typescript --project-id bsjdgwmveokanclqwtvx > /dev/null 2>&1 || echo "gen types: 앱은 Dart 모델 수동 — Plan 5에서 formatStatus enum 추가"
```
Expected: 이 Plan에서 Dart 표시 변경은 없음. `format_status`는 Plan 5(앱/검수 UI)에서 `enum FormatStatus`로 타입화. 여기선 마이그레이션만 완료.

- [ ] **Step 5: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
git add supabase/migrations/20260717*_tournament_format_pipeline.sql
git commit -m "feat(db): 요강 정형화 상태 컬럼·claim/complete/reject/fail RPC·트리거

- format_status(text+CHECK) + lease(processing/claim_token/claimed_at) + staged + embedding_input_revision
- durable claim/complete(stale-write 가드)/reject/fail RPC, service_role GRANT
- invalidate_tournament_embedding revision++; format_* 변조 차단 트리거
- 백필 pending 50 / skipped 31

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Plan 1 범위):** §5 컬럼→Task1, §6 RPC 3종+claim→Task4·5, §6 GRANT/search_path→Task5·6, §7 embedding revision→Task3, §11-2 변조차단→Task3, §11-3 hardening→Task4·5(search_path), §12 백필→Task7, §14 마이그레이션 순서·NOTIFY→Task8. Plan 1 밖(다음 계획): 크롤러(§8)=Plan2, format-pending Edge(§9·10)=Plan3, embed-pending optimistic write(§7)=Plan4, 검수 UI·앱 타입(§12·13)=Plan5.

**Placeholder scan:** 타임스탬프 `HHMMSS`만 실행 시 확정(의도적). 그 외 실제 SQL·검증쿼리·기대값 모두 기재. 통과.

**Type consistency:** claim이 반환하는 `claim_token/document_id/content_hash`를 complete가 `p_token/p_document_id/p_source_hash`로 소비 — 일치. `format_pending_complete` 시그니처(13파라미터)가 Task5·6 GRANT에서 동일. `format_staged` jsonb object, `format_flags` jsonb array CHECK 일치.

---

## Execution Handoff

이 Plan은 **DB 파운데이션**으로, Plan 2~5의 전제다. 실행 후 다음 계획(크롤러→Edge→임베딩→검수UI)을 순차 작성한다.
