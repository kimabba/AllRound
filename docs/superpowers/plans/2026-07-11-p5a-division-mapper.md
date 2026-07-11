# P5a DB 기반 범용 부서 해석기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 크롤러의 하드코딩 부서 KEYWORD_MAP을 제거하고, 크롤 시점에 `tennis_divisions.synonyms`(org별)를 읽어 매핑하는 범용 해석기로 대체해 블로커 #3(부서정보 3중 하드코딩)을 해소한다.

**Architecture:** 순수 함수 `mapDivisionsByDict(text, dict)`(신규 모듈 `_shared/crawler/divisions.ts`)가 부서 사전으로 매핑하고, `loadDivisionDict(supabase, orgCode)`가 크롤 시점에 사전을 로드한다. gnuboard 파서는 크롤 1회당 사전을 로드해 detail마다 이 해석기를 호출하며, `crawler.ts`의 `extractSidoStdDivisions` 하드코딩은 삭제된다. 순수 코드(마이그레이션 없음).

**Tech Stack:** Deno, TypeScript. 테스트 `deno test`, 타입 `deno check`. 파서 DB 접근은 `ctx.audit.supabase`(SupabaseClient). 배포 `supabase functions deploy crawl-dispatch --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json`.

## Global Constraints

- **마이그레이션 없음** — 순수 코드. `tennis_divisions`의 기존 synonyms를 읽기만 함(P1 시드).
- **gj/jn 동작 보존** — P1 시드 synonyms가 기존 KEYWORD_MAP과 일치(gj_m_gold {골드부,골드} 등). 매핑 결과 codes **집합**이 동일해야 함(순서 무관 — eligible_grades는 `&&`).
- **unmapped 처리 = A**: 사전 미매칭 시 `codes=[]`(비움). 기존 "오픈+일반 기본값" 폴백 **제거**. 원문은 `division_label_local`에 저장, draft 검수에서 보정.
- **TS `any` 금지**. CI가 warning도 에러 처리 — unused import/symbol 남기지 말 것.
- **셀프 머지**: CI 통과 + 리뷰 후 정상 머지 OK. `--admin` 금지.
- **배포+라이브 스모크는 컨트롤러가 수행**(프로덕션 Edge Function 배포 — 서브에이전트 범위 밖).

---

### Task 1: mapDivisionsByDict 순수 해석기 + 테스트

**Files:**
- Create: `supabase/functions/_shared/crawler/divisions.ts`
- Test: `supabase/functions/tests/crawler_edge_cases_test.ts` (기존 extractSidoStdDivisions 테스트를 mapDivisionsByDict로 이관)

**Interfaces:**
- Produces:
  - `interface DivisionDictRow { code: string; synonyms: string[]; label_ko: string }`
  - `mapDivisionsByDict(text: string, dict: DivisionDictRow[]): { codes: string[]; label: string; unmapped: boolean }` — 각 행의 synonym이 text에 substring으로 있으면 code+label_ko 채택(dict 순서 유지). 하나도 없으면 `{ codes: [], label: '', unmapped: true }`.

- [ ] **Step 1: 테스트 작성 — 실패 확인용**

`supabase/functions/tests/crawler_edge_cases_test.ts` 상단 import에 추가:
```ts
import { mapDivisionsByDict, type DivisionDictRow } from '../_shared/crawler/divisions.ts';
```

기존 `extractSidoStdDivisions` import·테스트 블록(131~167행 근처, `// ---- extractSidoStdDivisions 엣지 케이스 ----` 부터 마지막 관련 Deno.test까지)을 아래로 **교체**. 먼저 gj 사전 fixture(P1 시드 미러)를 정의:

```ts
// gj 부서 사전 fixture (P1 tennis_divisions 시드 미러, code 기준 정렬)
const GJ_DICT: DivisionDictRow[] = [
  { code: 'gj_m_open', synonyms: ['오픈부', '남자오픈', '오픈'], label_ko: '오픈부' },
  { code: 'gj_m_gold', synonyms: ['골드부', '골드'], label_ko: '골드부' },
  { code: 'gj_m_general', synonyms: ['남자일반부', '일반부', '남자일반'], label_ko: '일반부' },
  { code: 'gj_m_instructor', synonyms: ['지도자부', '지도자'], label_ko: '지도자부' },
  { code: 'gj_m_masters', synonyms: ['마스터즈부', '마스터즈'], label_ko: '마스터즈부' },
  { code: 'gj_m_rookie', synonyms: ['남자신인부', '신인부', '신인'], label_ko: '신인부' },
  { code: 'gj_m_veteran', synonyms: ['베테랑부', '베테랑'], label_ko: '베테랑부' },
  { code: 'gj_m_beginner', synonyms: ['초급자부', '비입상자부', '초급자'], label_ko: '초급자부' },
  { code: 'gj_w_open', synonyms: ['여자오픈부', '여자오픈'], label_ko: '여자오픈부' },
  { code: 'gj_w_winner', synonyms: ['우승자부', '여자우승자', '국화', '금배'], label_ko: '여자우승자부' },
  { code: 'gj_w_rookie', synonyms: ['여자신인부', '여자신인', '개나리'], label_ko: '여자신인부' },
  { code: 'gj_couple', synonyms: ['부부부', '부부'], label_ko: '부부부' },
  { code: 'gj_cross', synonyms: ['크로스'], label_ko: '크로스대회' },
];
const sorted = (a: string[]) => [...a].sort();

Deno.test('mapDivisionsByDict: 미매칭 → 비움 + unmapped=true (기본값 폴백 없음)', () => {
  const r = mapDivisionsByDict('제5회 영암 대회', GJ_DICT);
  assertEquals(r.codes, []);
  assertEquals(r.unmapped, true);
});

Deno.test('mapDivisionsByDict: "골드부" 단일 매칭', () => {
  const r = mapDivisionsByDict('골드부 경기일정', GJ_DICT);
  assertEquals(r.codes, ['gj_m_gold']);
  assertEquals(r.label, '골드부');
  assertEquals(r.unmapped, false);
});

Deno.test('mapDivisionsByDict: 복수 매칭 — "오픈" substring이 여자오픈부에도 걸림 (집합 동치)', () => {
  const r = mapDivisionsByDict('골드부 일반부 여자오픈부 대회', GJ_DICT);
  assertEquals(sorted(r.codes), sorted(['gj_m_open', 'gj_m_gold', 'gj_m_general', 'gj_w_open']));
});

Deno.test('mapDivisionsByDict: "부부부" 매칭', () => {
  const r = mapDivisionsByDict('부부부 대회', GJ_DICT);
  assertEquals(r.codes, ['gj_couple']);
});

Deno.test('mapDivisionsByDict: "개나리"(synonym) → 여자신인부', () => {
  const r = mapDivisionsByDict('개나리부 대회', GJ_DICT);
  assertEquals(r.codes, ['gj_w_rookie']);
});

Deno.test('mapDivisionsByDict: 빈 사전 → unmapped', () => {
  const r = mapDivisionsByDict('골드부', []);
  assertEquals(r.codes, []);
  assertEquals(r.unmapped, true);
});
```

기존 파일에 이미 `import { assertEquals } ...`가 있으면 중복 추가하지 말 것.

- [ ] **Step 2: 테스트 실행 → 실패 확인**

Run: `cd supabase/functions && deno test tests/crawler_edge_cases_test.ts --allow-env --allow-read`
Expected: FAIL — `divisions.ts` / `mapDivisionsByDict` 미존재(import 에러).

- [ ] **Step 3: divisions.ts 구현**

`supabase/functions/_shared/crawler/divisions.ts` 생성:
```ts
// _shared/crawler/divisions.ts
// tennis_divisions 사전을 단일 진실로 삼는 범용 부서 해석기.
// 협회별 하드코딩 KEYWORD_MAP을 대체(블로커 #3).

import type { SupabaseClient } from '@supabase/supabase-js';

export interface DivisionDictRow {
  code: string;
  synonyms: string[];
  label_ko: string;
}

/**
 * 대회 텍스트에서 부서 코드 추출. dict의 각 행에 대해 synonym 중 하나라도
 * text에 substring으로 존재하면 그 code를 채택(dict 순서 유지).
 * 하나도 안 맞으면 unmapped=true, codes=[] (기본값 추측 안 함 — draft 검수에서 보정).
 */
export function mapDivisionsByDict(
  text: string,
  dict: DivisionDictRow[],
): { codes: string[]; label: string; unmapped: boolean } {
  const codes: string[] = [];
  const labels: string[] = [];
  for (const row of dict) {
    if (row.synonyms.some((kw) => text.includes(kw))) {
      codes.push(row.code);
      labels.push(row.label_ko);
    }
  }
  return { codes, label: labels.join(' · '), unmapped: codes.length === 0 };
}

/**
 * 크롤 시점에 org의 활성 부서 사전 로드. crawl당 1회 호출 권장.
 */
export async function loadDivisionDict(
  supabase: SupabaseClient,
  orgCode: string,
): Promise<DivisionDictRow[]> {
  const { data, error } = await supabase
    .from('tennis_divisions')
    .select('code, synonyms, label_ko')
    .eq('org_code', orgCode)
    .eq('is_active', true)
    .order('code');
  if (error) throw new Error(`loadDivisionDict(${orgCode}) 실패: ${error.message}`);
  return (data ?? []) as DivisionDictRow[];
}
```

- [ ] **Step 4: 테스트·타입 통과 확인**

Run: `cd supabase/functions && deno test tests/crawler_edge_cases_test.ts --allow-env --allow-read && deno check _shared/crawler/divisions.ts`
Expected: 신규 6개 테스트 PASS. 타입 에러 없음.

- [ ] **Step 5: 커밋**

```bash
git add supabase/functions/_shared/crawler/divisions.ts supabase/functions/tests/crawler_edge_cases_test.ts
git commit -m "feat(crawl): DB기반 범용 부서 해석기 mapDivisionsByDict + loadDivisionDict

- tennis_divisions.synonyms를 단일 진실로 매핑(블로커 #3 근본책)
- unmapped 시 codes=[](기본값 폴백 없음), draft 검수에서 보정(결정 A)
- 순수 함수 단위 테스트 6개(mock gj 사전)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: gnuboard 파서를 DB 사전 매핑으로 이관 + extractSidoStdDivisions 제거

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts` (import, fetchDetail 시그니처 150~155·호출 244~247, 메인 fn 사전로드 + fetchDetail 호출부 ~425)
- Modify: `supabase/functions/_shared/crawler.ts` (`extractSidoStdDivisions` 함수 + KEYWORD_MAP 삭제)

**Interfaces:**
- Consumes: `mapDivisionsByDict`, `loadDivisionDict`, `DivisionDictRow` (Task 1). `ctx.audit.supabase: SupabaseClient`.

- [ ] **Step 1: 파서 — 사전 로드 + fetchDetail이 dict를 받도록 이관**

`gnuboard_sub5_5_contest.ts`:

(a) import(27행 근처)에서 `extractSidoStdDivisions,` 제거하고 상단 import 블록에 추가:
```ts
import { loadDivisionDict, mapDivisionsByDict, type DivisionDictRow } from '../divisions.ts';
```

(b) `fetchDetail` 시그니처(150~155행) — `org: string` 파라미터를 `dict: DivisionDictRow[]`로 교체:
```ts
async function fetchDetail(
  detailUrl: string,
  region: string,
  titleHint: string,
  dict: DivisionDictRow[],
): Promise<{ rawHtml: string; tournament: CrawlerTournament | null } | null> {
```

(c) 부서 추출 호출부(244~247행) 교체:
```ts
  const { codes: gradeCodes, label: divisionLabel } = mapDivisionsByDict(
    `${title} ${bodyText}`,
    dict,
  );
```

(d) 메인 파서 fn(348행~): `org` 결정부(P4에서 `const org = source.org_code; if(!org) return error` 형태) 바로 뒤에 사전 로드 추가하고, fetchDetail 호출(~425행)의 `org` 인자를 `dict`로 교체:
```ts
  // org 사전을 crawl당 1회 로드(detail마다 재조회 금지)
  const dict = await loadDivisionDict(ctx.audit.supabase, org);
```
```ts
      const result = await fetchDetail(item.url, region, item.title, dict);
```
(`org` 변수는 loadDivisionDict 인자로 계속 쓰이므로 unused 되지 않음.)

- [ ] **Step 2: crawler.ts에서 extractSidoStdDivisions + KEYWORD_MAP 삭제**

`_shared/crawler.ts`의 `export function extractSidoStdDivisions(...) { ... }` 전체(문서주석 702행 근처 ~ 함수 끝 752행 근처) 삭제. `extractTennisGradesFromText` deprecated 스텁은 건드리지 않음.

- [ ] **Step 3: 타입·테스트·잔존참조 확인**

Run:
```
cd supabase/functions && deno check _shared/crawler/parsers/gnuboard_sub5_5_contest.ts _shared/crawler.ts && deno test tests/ --allow-env --allow-read
```
Expected: 타입 에러 없음. 전체 테스트 PASS. 그리고:
`grep -rn "extractSidoStdDivisions" supabase/functions` → **빈 결과**(완전 제거).

- [ ] **Step 4: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts supabase/functions/_shared/crawler.ts
git commit -m "refactor(crawl): gnuboard 파서를 DB 사전 매핑으로 이관 + extractSidoStdDivisions 제거

- 크롤당 loadDivisionDict(org) 1회 로드 → fetchDetail이 dict 받아 mapDivisionsByDict 호출
- crawler.ts의 하드코딩 KEYWORD_MAP/extractSidoStdDivisions 완전 삭제(블로커 #3 해소)
- gj/jn 동작 보존(시드 synonyms 동일), 배포+라이브스모크는 컨트롤러 수행

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: (컨트롤러) 배포 + 라이브 스모크** — 이 스텝은 구현 서브에이전트가 아니라 컨트롤러가 머지 후 수행.

배포: `supabase functions deploy crawl-dispatch --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json`
스모크: `execute_sql`로 `update crawl_sources set last_crawled_at=null, last_etag=null where slug in ('tennis-gwangju','tennis-jeonnam')` 후 크롤 유발 → gj/jn 대회 eligible_grades가 여전히 `gj_*`/`jn_*` 코드인지, last_status가 error 아닌지 확인.

---

## Self-Review

**1. Spec coverage:**
- 범용 해석기 mapDivisionsByDict → T1 ✓
- 사전 로딩 loadDivisionDict(org별, 1회) → T1(정의) + T2S1(d 사용) ✓
- gj/jn 이관 + KEYWORD_MAP 하드코딩 제거 → T2S1·T2S2 ✓
- unmapped=A(비움, 폴백 제거) → T1 mapper 반환 codes=[] + T1 테스트 ✓
- 순서 무관 집합 동치 테스트 → T1S1 sorted() 단언 ✓
- 검증: deno test 단위 + gj/jn 동치 + 라이브 스모크 → T1S4·T2S3·T2S5 ✓
- 마이그레이션 없음 → 계획에 DB 스키마 변경 없음 ✓
- 범위 밖(KATO=P5b, 어드민 큐 UI, 클라 하드코딩=P7) → 미포함 ✓

**2. Placeholder scan:** 없음. 모든 코드·명령·기대값 명시.

**3. Type consistency:** `DivisionDictRow{code,synonyms,label_ko}`, `mapDivisionsByDict(text, dict)→{codes,label,unmapped}`, `loadDivisionDict(supabase, orgCode)→Promise<DivisionDictRow[]>`, `fetchDetail(...,dict: DivisionDictRow[])` — 전 태스크 일관.
