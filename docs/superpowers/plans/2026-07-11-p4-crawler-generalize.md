# P4 크롤러 일반화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 크롤러가 협회를 slug로 추측하지 않고 `crawl_sources.org_code`에서 읽게 하고, 부서추출 함수의 org를 gj/jn 제한에서 일반 string으로 풀어 비-gj/jn 파서의 전제조건을 놓는다.

**Architecture:** Deno Edge Function. 순수 코드 변경(마이그레이션 없음). (2) `extractGJDivisions`→`extractSidoStdDivisions(org: string)` rename+일반화는 `deno test`로 TDD 검증. (1) slug 추론 제거는 `CrawlSource.org_code` 추가 + 파서가 그것을 읽고 없으면 fail loud; `deno check` + 배포 후 라이브 스모크로 검증.

**Tech Stack:** Deno, TypeScript. 테스트 `deno test`, 타입 `deno check`. 배포 `supabase functions deploy crawl-dispatch --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json`.

## Global Constraints

- **마이그레이션 없음** — 순수 코드 변경. DB 스키마 불변.
- **기존 gj/jn 동작 보존** — org_code가 slug 추론과 동일 값(gj/jn) 산출.
- **범위 밖**: (3) 미매칭 어드민 검수 큐, (4) EUC-KR 디코딩, KEYWORD_MAP의 DB화 → 전부 P5. KEYWORD_MAP·"오픈+일반" 폴백은 그대로 둔다.
- **Dart `dynamic` / TS `any` 금지**(CLAUDE.md). 새 필드는 `string | null` 명시.
- **셀프 머지**: CI 통과 + 리뷰 후 정상 머지 OK. `--admin` 금지.
- **CI가 warning도 에러 처리** — unused import/element 남기지 말 것.

---

### Task 1: extractGJDivisions → extractSidoStdDivisions rename + org 일반화

**Files:**
- Modify: `supabase/functions/_shared/crawler.ts` (함수 정의 ~710)
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts` (import 27, 호출 244, fetchDetail 시그니처 154)
- Test: `supabase/functions/tests/crawler_edge_cases_test.ts`

**Interfaces:**
- Produces: `extractSidoStdDivisions(text: string, org: string): { codes: string[]; label: string }` — 기존 `extractGJDivisions`와 동일 동작(KEYWORD_MAP·폴백 불변), org 타입만 `'gj'|'jn'`→`string`.

- [ ] **Step 1: 테스트를 새 이름·일반 org로 갱신하고 실패 확인**

`supabase/functions/tests/crawler_edge_cases_test.ts`에서 import와 6개 테스트를 `extractSidoStdDivisions`로 바꾸고, 임의 org 테스트 2개를 추가한다. 131~167행 블록을 아래로 교체:

```ts
// ---- extractSidoStdDivisions 엣지 케이스 ----

Deno.test('extractSidoStdDivisions: 아무 부서도 매칭 안 되면 기본값 (오픈부 + 일반부)', () => {
  const result = extractSidoStdDivisions('제5회 영암 대회', 'gj');
  assertEquals(result.codes, ['gj_m_open', 'gj_m_general']);
  assertEquals(result.label, '오픈부 · 일반부');
});

Deno.test('extractSidoStdDivisions: "골드부" 단일 매칭', () => {
  const result = extractSidoStdDivisions('골드부 경기일정', 'gj');
  assertEquals(result.codes, ['gj_m_gold']);
  assertEquals(result.label, '골드부');
});

Deno.test('extractSidoStdDivisions: 복수 부서 매칭 (골드부 + 일반부 + 여자오픈부)', () => {
  const result = extractSidoStdDivisions('골드부 일반부 여자오픈부 대회', 'jn');
  assertEquals(result.codes, ['jn_m_open', 'jn_m_gold', 'jn_m_general', 'jn_w_open']);
  assertEquals(result.label, '오픈부 · 골드부 · 일반부 · 여자오픈부');
});

Deno.test('extractSidoStdDivisions: "부부부" 매칭', () => {
  const result = extractSidoStdDivisions('부부부 대회', 'gj');
  assertEquals(result.codes, ['gj_couple']);
  assertEquals(result.label, '부부부');
});

Deno.test('extractSidoStdDivisions: "크로스" 매칭', () => {
  const result = extractSidoStdDivisions('크로스 대회', 'jn');
  assertEquals(result.codes, ['jn_cross']);
  assertEquals(result.label, '크로스대회');
});

Deno.test('extractSidoStdDivisions: org "jn" → 전남 prefix', () => {
  const result = extractSidoStdDivisions('신인부 대회', 'jn');
  assertEquals(result.codes, ['jn_m_rookie']);
});

// 일반화: 임의 org prefix 동작 (비-gj/jn)
Deno.test('extractSidoStdDivisions: 임의 org "kta" prefix', () => {
  const result = extractSidoStdDivisions('골드부 대회', 'kta');
  assertEquals(result.codes, ['kta_m_gold']);
});

Deno.test('extractSidoStdDivisions: 임의 org "seoul" prefix', () => {
  const result = extractSidoStdDivisions('신인부 대회', 'seoul');
  assertEquals(result.codes, ['seoul_m_rookie']);
});
```

10행 근처 주석의 `extractGJDivisions 엣지 케이스`, 17행 import 심볼도 `extractSidoStdDivisions`로 바꾼다.

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `cd supabase/functions && deno test tests/crawler_edge_cases_test.ts`
Expected: FAIL — `extractSidoStdDivisions` is not exported (import error), 또는 미정의.

- [ ] **Step 3: crawler.ts 함수 rename + org 타입 일반화**

`supabase/functions/_shared/crawler.ts`의 함수 정의(≈710행). 시그니처만 변경, 본문(KEYWORD_MAP, 매칭 루프, 폴백) 불변:

```ts
export function extractSidoStdDivisions(
  text: string,
  org: string,
): { codes: string[]; label: string } {
```

문서 주석(702~708행)의 "광주/전남 … org: 'gj' | 'jn'"를 "sido_std 부서체계(오픈/골드/일반/신인…)를 쓰는 협회 공고 텍스트에서 부서 코드 추출. org: 협회 코드 prefix(예: 'gj','jn','kta')"로 갱신.

- [ ] **Step 4: 파서의 import·호출·fetchDetail 시그니처 갱신**

`gnuboard_sub5_5_contest.ts`:
- 27행 import: `extractGJDivisions,` → `extractSidoStdDivisions,`
- 244행 호출: `extractGJDivisions(` → `extractSidoStdDivisions(`
- 154행 fetchDetail 시그니처: `org: 'gj' | 'jn',` → `org: string,`

- [ ] **Step 5: 테스트·타입 통과 확인**

Run: `cd supabase/functions && deno test tests/crawler_edge_cases_test.ts && deno check crawler-dispatch 2>/dev/null; deno check _shared/crawler.ts _shared/crawler/parsers/gnuboard_sub5_5_contest.ts`
Expected: 8개 테스트 PASS. 타입 에러 없음. `extractGJDivisions` 잔존 참조 0 (`grep -rn extractGJDivisions supabase/functions` → 빈 결과).

- [ ] **Step 6: 커밋**

```bash
git add supabase/functions/_shared/crawler.ts supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts supabase/functions/tests/crawler_edge_cases_test.ts
git commit -m "refactor(crawl): extractGJDivisions → extractSidoStdDivisions(org: string)

- org 파라미터 'gj'|'jn' → string 일반화(비-gj/jn 파서 전제조건)
- 이름을 division_scheme='sido_std'와 일치시켜 GJ 한정 오해 제거
- 본문(KEYWORD_MAP·폴백) 불변. 임의 org prefix 테스트 2개 추가

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: slug 추론 제거 — source.org_code 사용 + fail loud

**Files:**
- Modify: `supabase/functions/_shared/crawler/types.ts` (CrawlSource 인터페이스 15~19)
- Modify: `supabase/functions/crawl-dispatch/index.ts` (SourceRow 36~46, SELECT 111~113, sourceArg 163~166)
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts` (420행)

**Interfaces:**
- Consumes: `crawl_sources.org_code`(P1 백필, 활성 tennis 소스 gj/jn 채워짐).
- Produces: `CrawlSource.org_code: string | null`.

- [ ] **Step 1: CrawlSource 인터페이스에 org_code 추가**

`_shared/crawler/types.ts` 15~19행:

```ts
export interface CrawlSource {
  slug: string;
  url: string;
  region: string | null;
  org_code: string | null;
}
```

- [ ] **Step 2: 디스패처 — SourceRow·SELECT·조립에 org_code 반영**

`crawl-dispatch/index.ts`:
- SourceRow(36~46)에 필드 추가: `org_code: string | null;`
- SELECT(111~113): 컬럼 목록에 `org_code` 추가 →
  `'id, slug, url, region, org_code, parser_module, enabled, last_crawled_at, last_etag, last_modified'`
- sourceArg(163~166):
  ```ts
  const sourceArg: CrawlSource = {
    slug: row.slug,
    url: row.url,
    region: row.region,
    org_code: row.org_code,
  };
  ```

- [ ] **Step 3: 파서 — slug 추론을 org_code로 교체 + fail loud**

`gnuboard_sub5_5_contest.ts` 420행:

```ts
  // 4) 상세 페이지 처리 — 협회는 crawl_sources.org_code 로 결정(추론 금지).
  const org = source.org_code;
  if (!org) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: 'crawl_sources.org_code 미설정 — 파서가 org를 추론하지 않는다',
    };
  }
```

(기존 `const org: 'gj' | 'jn' = source.slug.includes('gwangju') ? 'gj' : 'jn';` 삭제. 이후 `fetchDetail(..., org)` 호출은 org: string 이므로 그대로 동작.)

- [ ] **Step 4: 타입·테스트 통과 확인**

Run: `cd supabase/functions && deno check crawl-dispatch/index.ts _shared/crawler/parsers/gnuboard_sub5_5_contest.ts _shared/crawler/types.ts && deno test tests/`
Expected: 타입 에러 없음. 전체 테스트 PASS. `grep -rn "includes('gwangju')" supabase/functions` → 빈 결과.

- [ ] **Step 5: 배포 + 라이브 스모크**

배포:
```bash
supabase functions deploy crawl-dispatch --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json
```

강제 재크롤(스냅샷 기준): 배포 전 `execute_sql`로 두 소스의 gj_/jn_ 대회 샘플 존재 확인 후, force 크롤을 유발한다. 강제 재크롤은 메모리 규율에 따라:
```sql
update crawl_sources set last_crawled_at=null, last_etag=null where slug in ('tennis-gwangju','tennis-jeonnam');
```
그 뒤 dispatch 호출(어드민 "수동 실행" 또는 `POST {slug, force:true}`)로 각 소스 실행.

기대(검증): 실행 후 `execute_sql`로 확인 —
- tennis-gwangju 유래 대회의 `eligible_grades`가 여전히 `gj_*` prefix(전남 아님).
- tennis-jeonnam 유래가 `jn_*` prefix.
- `crawl_sources.last_status`가 'error' 아님(org_code 정상 해결).

org_code가 slug 추론과 동일 결과를 냄을 확인 → 회귀 없음.

- [ ] **Step 6: 커밋**

```bash
git add supabase/functions/_shared/crawler/types.ts supabase/functions/crawl-dispatch/index.ts supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts
git commit -m "feat(crawl): slug 추론 제거 — source.org_code 사용(블로커 #4)

- CrawlSource.org_code 추가, 디스패처가 crawl_sources.org_code 전달
- 파서: slug.includes('gwangju')?'gj':'jn' → source.org_code
- org_code 미설정 시 조용한 'jn' 대신 status='error'(fail loud)
- 배포 crawl-dispatch, 라이브 스모크로 gj/jn 회귀 없음 확인

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- (1) slug 추론 제거: CrawlSource.org_code(T2S1) + 디스패처(T2S2) + 파서 org_code+fail loud(T2S3) ✓
- (2) extractGJDivisions 일반화+rename: crawler.ts(T1S3) + 파서 호출부(T1S4) + 테스트(T1S1) ✓
- 검증 (2) deno test 비-gj/jn org → T1S1 신규 테스트 2개 ✓
- 검증 (1) deno check + 라이브 스모크 → T2S4·T2S5 ✓
- 범위 밖(큐·EUC-KR·KEYWORD_MAP DB화) → 계획 미포함 ✓
- fail loud(org_code 없으면 error) → T2S3 ✓

**2. Placeholder scan:** 없음. 모든 코드·명령·기대값 명시.

**3. Type consistency:** `extractSidoStdDivisions(text, org: string)`, `CrawlSource.org_code: string | null`, `SourceRow.org_code: string | null` — 전 태스크 일관. Task 1이 rename한 심볼을 Task 2가 재참조하지 않음(직교).
