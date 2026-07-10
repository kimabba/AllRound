# P2 매칭 일반화 (equiv_group 드롭인) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `expand_gj_jn_codes`의 하드코딩 gj↔jn 치환을 `tennis_divisions.equiv_group` 사전 조회로 재구현하되 시그니처를 유지해 6개 RPC를 무손상으로 둔다.

**Architecture:** 신규 함수 `expand_division_codes(text[])→text[]`가 equiv_group 형제 코드를 반환하고, 기존 `expand_gj_jn_codes`는 그것을 호출하는 얇은 별칭으로 재정의된다. 단일 마이그레이션 파일 하나. 6개 RPC(072/075/076/078/079/084)는 함수 시그니처가 불변이라 수정하지 않는다.

**Tech Stack:** Supabase Postgres (SQL 함수), 마이그레이션은 memory 규율에 따라 `execute_sql`로 직접 적용(`db push` 금지). 프로젝트 ref `bsjdgwmveokanclqwtvx`.

## Global Constraints

- **`db push` 금지** — 히스토리 붕괴(JY-116). 마이그레이션은 `mcp__claude_ai_Supabase__execute_sql` 또는 `apply_migration`으로 직접 적용하고, `.sql` 파일은 기록용으로 리포에 커밋.
- **RPC/함수 DROP·CREATE 후** 반드시 `NOTIFY pgrst, 'reload schema'`.
- **시그니처 불변** — `expand_gj_jn_codes(text[])→text[]` 는 절대 바꾸지 않는다(6 RPC 의존).
- **RLS/정책** — 새 테이블 없음(함수만), 정책 변경 불요.
- **셀프 머지 금지** — PR → CI → 리뷰 → kimabba 머지.

---

### Task 1: expand_division_codes + expand_gj_jn_codes 별칭 재정의

**Files:**
- Create: `supabase/migrations/085_expand_division_codes_equiv.sql`

**Interfaces:**
- Consumes: `public.tennis_divisions(code, equiv_group)` (P1 시드, 라이브).
- Produces:
  - `public.expand_division_codes(codes text[]) → text[]` (STABLE) — 각 입력 코드의 자기 자신 + 동일 `equiv_group` 형제 코드 집합.
  - `public.expand_gj_jn_codes(codes text[]) → text[]` (STABLE) — `expand_division_codes`의 별칭. 6 RPC가 이 이름으로 호출.

- [ ] **Step 1: 마이그레이션 전 동등성 스냅샷 캡처 (검증 기준선)**

`execute_sql`로 실행하고 결과를 보관(마이그레이션 후 비교용):

```sql
-- (a) 5개 user_tennis_orgs의 현행 확장 결과
select user_id, org, division_codes,
       public.expand_gj_jn_codes(division_codes) as expanded_old
from user_tennis_orgs order by user_id, org;

-- (b) 대표 유저별 tournaments_for_user 매칭 대회 id 집합 (only_my_grade=true)
--     각 user_id 에 대해:
--     select array_agg(id order by id) from tournaments_for_user(:uid, 'tennis', null,null,null, true);
```

기대: 결과를 스크래치패드/메모리에 기록. 이게 "diff=0" 판정의 기준선.

- [ ] **Step 2: 마이그레이션 SQL 파일 작성**

`supabase/migrations/085_expand_division_codes_equiv.sql`:

```sql
-- 085: P2 매칭 일반화 — expand_gj_jn_codes 하드코딩 gj↔jn 치환을
--      tennis_divisions.equiv_group 사전 조회로 재구현.
--      시그니처 불변 → 6개 RPC(072/075/076/078/079/084) 무손상.
--      비파괴: 라이브 데이터 동등성 사전 확인(유저코드·대회등급 전부 사전 존재).

-- 신규 정식 함수: equiv_group 기반 확장
CREATE OR REPLACE FUNCTION public.expand_division_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT c), '{}')
  FROM (
    -- 원본 코드 pass-through (사전 미존재/equiv 없음도 자기 자신 유지)
    SELECT unnest(codes) AS c
    UNION
    -- 같은 equiv_group 형제 코드
    SELECT sib.code
    FROM unnest(codes) AS input_code
    JOIN public.tennis_divisions d   ON d.code = input_code AND d.equiv_group IS NOT NULL
    JOIN public.tennis_divisions sib ON sib.equiv_group = d.equiv_group
  ) sub
  WHERE c IS NOT NULL;
$$;

-- 별칭 재정의: 하드코딩 gj↔jn 치환 제거, IMMUTABLE→STABLE
CREATE OR REPLACE FUNCTION public.expand_gj_jn_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$ SELECT public.expand_division_codes(codes); $$;

NOTIFY pgrst, 'reload schema';
```

- [ ] **Step 3: 마이그레이션 적용**

`execute_sql`로 위 파일 내용 실행(`db push` 금지). `NOTIFY pgrst`까지 포함.

기대: 에러 없이 두 함수 재정의 완료.

- [ ] **Step 4: 단위 동등/신규동치 단언**

`execute_sql`:

```sql
select
  -- 구 동작 == 신 동작 (gj/jn 트윈)
  public.expand_division_codes('{gj_m_gold}') @> '{gj_m_gold,jn_m_gold}'
    and public.expand_division_codes('{gj_m_gold}') <@ '{gj_m_gold,jn_m_gold}'  as gjjn_ok,
  -- 신규 협회 경계 동치
  public.expand_division_codes('{kta_senior_60}') @> '{kstf_60}'                as senior_equiv_ok,
  -- pass-through (사전 미존재)
  public.expand_division_codes('{nonexistent_code}') = '{nonexistent_code}'      as passthrough_ok,
  -- 와일드카드 회귀 방지: gj2_foo 는 jn류 생성 안 함
  not (public.expand_division_codes('{gj2_foo}') && (
        select array_agg(code) from tennis_divisions where code like 'jn\_%')) as wildcard_ok;
```

기대: 네 컬럼 모두 `true`.

- [ ] **Step 5: 마이그레이션 후 동등성 재스냅샷 → diff=0 단언**

Step 1과 동일한 두 쿼리(a)(b)를 다시 실행. Step 1 결과와 비교.

기대:
- (a) `expand_gj_jn_codes(division_codes)` 결과가 5개 행 모두 Step 1과 동일(집합 동등, 정렬 무관).
- (b) 각 유저의 `tournaments_for_user` 매칭 대회 id 집합이 Step 1과 **완전 동일(diff=0)**.

diff가 있으면 즉시 롤백 검토(마이그레이션은 함수 재정의라 이전 정의로 `CREATE OR REPLACE` 되돌리기 가능).

- [ ] **Step 6: 커밋**

```bash
git add supabase/migrations/085_expand_division_codes_equiv.sql
git commit -m "feat(db): P2 매칭 일반화 — expand_gj_jn_codes를 equiv_group 사전조회로 재구현

- 신규 expand_division_codes(text[]): equiv_group 형제 확장
- expand_gj_jn_codes를 별칭으로 재정의(시그니처 불변, 6 RPC 무손상)
- 하드코딩 gj↔jn 치환·LIKE 와일드카드 버그 제거
- senior:60 등 협회 경계 동치 자동 확장
- 라이브 동등성 검증: gj/jn/kta 유저 tournaments_for_user diff=0

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- 신규 `expand_division_codes` → Task 1 Step 2 ✓
- 별칭 재정의(시그니처 유지) → Step 2 ✓
- `NOTIFY pgrst` → Step 2/3 ✓
- IMMUTABLE→STABLE → Step 2 ✓
- 성공 기준 1(동등성 diff=0) → Step 1+5 ✓
- 성공 기준 2(gj_m_gold 단위 동등) → Step 4 ✓
- 성공 기준 3(senior 동치) → Step 4 ✓
- 성공 기준 4(pass-through) → Step 4 ✓
- 성공 기준 5(와일드카드 회귀) → Step 4 ✓
- 범위 밖(B skill_tier) → 계획에 미포함 ✓

**2. Placeholder scan:** 없음. 모든 SQL·명령·기대값 명시.

**3. Type consistency:** `expand_division_codes(text[])→text[]`, `expand_gj_jn_codes(text[])→text[]` — Task 전체에서 일관.

TDD 노트: DB 함수라 코드-우선 실패테스트 대신, Step 1의 사전 스냅샷이 회귀 기준선 역할을 하고 Step 4·5가 검증 게이트다. 이 도메인에 맞는 goal-driven 검증 구조.
