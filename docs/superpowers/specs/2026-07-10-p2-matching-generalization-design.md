# P2 — 매칭 일반화 (equiv_group 드롭인)

작성 2026-07-10 · 관련: `docs/team/REVIEW-nationwide-tennis-crawl.md`(로드맵 P2), P1 마이그레이션 `20260710020000_tennis_orgs_divisions_catalog.sql`.

## 배경

전국 확장 P1에서 부서 사전 테이블 `tennis_divisions`(48행, `equiv_group` 34개)를 라이브 시드했다. P2는 매칭 로직이 이 사전을 참조하도록 전환한다.

현행 매칭은 `expand_gj_jn_codes(text[]) → text[]`(072) 하나에 캡슐화돼 있고, 6개 RPC(072/075/076/078/079/084)가 동일 패턴으로 호출한다:

```sql
EXISTS (SELECT 1 FROM user_tennis_orgs uto
  WHERE uto.user_id = p_user_id
    AND public.expand_gj_jn_codes(uto.division_codes) && t.eligible_grades)
```

현행 `expand_gj_jn_codes`의 문제:
- 광주↔전남 치환이 SQL에 하드코딩(`code LIKE 'gj_%' THEN 'jn_' || substring(...)`).
- `LIKE 'gj_%'`의 `_`가 와일드카드라 `gj2_...` 같은 코드를 오매칭할 잠재 버그.
- 협회 경계 넘는 동치(예: KTA 시니어 60 ↔ KSTF 60)를 표현 불가.

## 범위

**포함(A):** `expand_gj_jn_codes`의 하드코딩 치환을 `tennis_divisions.equiv_group` 조회로 재구현. 시그니처 유지, gj/jn 동작 보존, 와일드카드 버그 제거, 타 협회 동치 자동 확장.

**제외(B, P2.5로 분리):** skill_tier 리콜 폴백(미등록 유저를 티어로 매칭). 6 RPC의 `EXISTS` 서브쿼리는 이번에 건드리지 않는다.

## 라이브 데이터 검증 (사전 확인 완료)

마이그레이션 전 실측으로 리스크 0 확인:
- 유저 등록 `division_codes` 전부 사전에 존재 (레거시 코드 없음).
- 대회 `eligible_grades` 전부 사전에 존재.
- gj/jn 코드 전부 `equiv_group` 보유.

→ 신 함수(사전 기반)와 구 함수(문자열 치환)의 출력이 라이브 도메인에서 동일함이 보장된다.

## 설계

### 신규 함수 `expand_division_codes`

```sql
CREATE OR REPLACE FUNCTION public.expand_division_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT c), '{}')
  FROM (
    -- 원본 코드 pass-through (사전 미존재/equiv 없음도 자기 자신은 유지)
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
```

동작:
- 각 입력 코드 → 자기 자신 + 같은 `equiv_group` 형제 전부.
- `equiv_group IS NULL`이거나 사전 미존재 → 자기 자신만 (pass-through).
- 형제 조인은 `is_active` 필터를 걸지 않는다(YAGNI: 비활성 코드는 어떤 `eligible_grades`에도 없어 `&&` 결과에 무해).

### 별칭 재정의 `expand_gj_jn_codes`

```sql
CREATE OR REPLACE FUNCTION public.expand_gj_jn_codes(codes text[])
RETURNS text[]
LANGUAGE sql STABLE
SET search_path = public
AS $$ SELECT public.expand_division_codes(codes); $$;
```

- 시그니처 `(text[]) → text[]` 불변 → 6개 RPC 무변경, PostgREST overload 문제 없음.
- `IMMUTABLE → STABLE`(테이블 읽기). 인덱스 미사용이라 무해. `CREATE OR REPLACE`로 volatility 변경 가능(DROP 불필요).

### 마이그레이션 후

```sql
NOTIFY pgrst, 'reload schema';
```

신규 함수 `expand_division_codes`가 PostgREST RPC로 노출되므로 스키마 리로드.

## 얻는 것 (공짜)

- `senior:60`(kta_senior_60 ↔ kstf_60), `senior:65` 등 협회 경계 넘는 동치가 하드코딩 없이 자동 매칭.
- 앞으로 신규 협회 부서에 `equiv_group`만 부여하면 매칭이 자동 확장(SQL 수정 불요).
- gj/jn 동작은 기존과 100% 동일.

## 성공 기준 (goal-driven 검증)

1. **동등성**: 마이그레이션 전후로 5개 user_tennis_orgs에 대한 `tournaments_for_user` 결과 집합 스냅샷 → gj/jn/kta 유저 **diff = 0**.
2. **단위 동등**: `expand_division_codes('{gj_m_gold}')` == `{gj_m_gold, jn_m_gold}` (구 동작 == 신 동작).
3. **신규 동치**: `expand_division_codes('{kta_senior_60}')` ⊇ `{kstf_60}` (협회 경계 동치 동작).
4. **pass-through**: `expand_division_codes('{nonexistent_code}')` == `{nonexistent_code}`.
5. **와일드카드 회귀 방지**: `expand_division_codes('{gj2_foo}')`가 `jn`류 코드를 만들어내지 않음(사전 미존재 → 자기 자신만).

## 파일

- 신규 마이그레이션: `supabase/migrations/085_expand_division_codes_equiv.sql`
  (두 함수 정의 + `NOTIFY pgrst`)

## 리스크

- 낮음. 함수 본문만 교체, 6 RPC 무손상, 라이브 데이터 동등성 사전 확인 완료.
- 유일한 미묘함: 향후 gj/jn 트윈이 없는 코드에 `equiv_group`을 잘못 부여하면 의도치 않은 확장 발생 → 사전 시드 관리 규율로 흡수(코드 문제 아님).
