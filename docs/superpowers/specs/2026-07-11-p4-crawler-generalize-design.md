# P4 — 크롤러 일반화 (slug 추론 제거 + 부서추출 일반화)

작성 2026-07-11 · 관련: `docs/team/REVIEW-nationwide-tennis-crawl.md`(로드맵 P4, 블로커 #4·#2), P1 마이그레이션(`crawl_sources.org_code` 백필), P3(enum→text 완료).

## 배경

크롤러(Deno Edge Function `crawl-dispatch` + `_shared/crawler/`)에 전국 확장 블로커 둘이 있다:
- **블로커 #4**: `gnuboard_sub5_5_contest.ts:420` `const org = source.slug.includes('gwangju') ? 'gj' : 'jn'` — gwangju 아닌 소스는 **전부 조용히 'jn'**. 3번째 소스 추가 즉시 사고.
- **블로커 #2(잔여)**: `extractGJDivisions(text, org: 'gj'|'jn')`가 org를 gj/jn로 제한 → 비-gj/jn 파서 불가.

P1이 `crawl_sources.org_code`를 백필해 뒀다(활성 테니스 소스: tennis-gwangju='gj', tennis-jeonnam='jn'). P4는 slug 추론을 이 컬럼 조회로 대체하고, 부서추출 함수의 org 제한을 푼다.

## 범위 (사용자 승인)

**포함:** (1) slug 추론 제거, (2) `extractGJDivisions` 일반화 + 이름 정리.

**제외 → P5:** (3) 미매칭 어드민 검수 큐, (4) EUC-KR 디코딩 헬퍼. KEYWORD_MAP 하드코딩의 DB화(블로커 #3)도 큐와 함께 P5. 이유: (3)(4)는 타 협회·EUC-KR 소스가 실제 들어와야(P5) 값이 생기고 검증 가능 — 지금 만들면 speculative.

## 설계

### (1) slug 추론 제거

- **`_shared/crawler/types.ts`** — `CrawlSource` 인터페이스에 `org_code: string | null` 추가.
- **`crawl-dispatch/index.ts`** — crawl_sources SELECT에 `org_code` 추가(현재 `id, slug, url, region, parser_module, ...`), CrawlSource 조립에 `org_code: row.org_code` 포함.
- **`_shared/crawler/parsers/gnuboard_sub5_5_contest.ts:420`** — `source.slug.includes('gwangju') ? 'gj' : 'jn'` 삭제. `const org = source.org_code;` 로 교체하고, `org`가 null/빈 문자열이면 **조용한 기본값 대신** 즉시 error CrawlResult 반환:
  ```
  if (!org) return { fetched_count:0, inserted_count:0, updated_count:0,
                     status:'error', error:'crawl_sources.org_code 미설정 — 파서가 org를 추론하지 않는다' };
  ```
  디스패처가 status='error'를 last_error로 기록(fail loud). region_code는 파서 org 로직에 불필요하므로 추가하지 않는다(YAGNI).

### (2) extractGJDivisions 일반화 + rename

- **`_shared/crawler.ts`** — `extractGJDivisions(text, org: 'gj'|'jn')` → **`extractSidoStdDivisions(text, org: string)`**. 본문(KEYWORD_MAP, 매칭 루프, "오픈+일반" 폴백)은 불변; `org` 타입만 string, 이름만 변경. (이름이 'GJ'인데 임의 org를 받는 모순 제거, DB `division_scheme='sido_std'`와 명명 일치. 내부 TS 함수라 외부 소비자 없음 → rename 안전.)
- **호출부 전부 갱신**: 파서 import(line 27)·호출(line 244), `fetchDetail` 시그니처(line 154 `org: 'gj'|'jn'` → `org: string`), 테스트 파일 `tests/crawler_edge_cases_test.ts`(import + 6개 호출 + 테스트명).
- KEYWORD_MAP·폴백은 그대로(범위 밖).

## 성공 기준 (검증)

1. **타입/컴파일**: `deno check` 통과(파서·디스패처·crawler.ts).
2. **단위 테스트** (`deno test`):
   - 기존 extractGJDivisions 테스트를 `extractSidoStdDivisions`로 rename해 전부 통과.
   - **신규**: `extractSidoStdDivisions('골드부 대회', 'kta')` → `codes`에 `kta_m_gold` 포함(임의 org prefix 동작 확인).
   - **신규**: `extractSidoStdDivisions('신인부', 'seoul')` → `seoul_m_rookie` 포함.
3. **라이브 스모크**(배포 후): tennis-gwangju force 크롤 → 여전히 `gj_*` eligible_grades 생성; tennis-jeonnam force → `jn_*` 생성(org가 org_code에서 정확히 해결됨). org_code 없는 소스는 status='error'.

## 파일

- 수정: `supabase/functions/_shared/crawler/types.ts`, `supabase/functions/crawl-dispatch/index.ts`, `supabase/functions/_shared/crawler.ts`, `supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts`, `supabase/functions/tests/crawler_edge_cases_test.ts`
- 배포: `crawl-dispatch` Edge Function (import_map.json 사용)

## 리스크

- 저. 기존 gj/jn 동작 보존(org_code가 slug 추론과 동일 값 산출), rename은 내부 함수라 안전.
- 마이그레이션 없음(순수 코드 변경). DB 스키마 불변.
- 배포 대상은 `crawl-dispatch` 하나. `_shared/`는 함께 번들됨.
- org_code 없는 소스를 error 처리하므로, 향후 소스 등록 시 org_code 필수 — 운영 주의(문서화).
