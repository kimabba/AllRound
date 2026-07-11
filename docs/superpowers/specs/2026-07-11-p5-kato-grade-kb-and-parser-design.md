# P5 (KATO) — 등급체계 KB 패턴 + KATO 부서 seed + KATO 파서

작성 2026-07-11 · 관련: P5a(`2026-07-11-p5a-division-mapper-design.md`, DB 기반 해석기), `docs/team/REVIEW-nationwide-tennis-crawl.md`(로드맵 P5), `docs/research/tennis-grade-systems.md`(§1.2 KATO). 전문가 패널 3인 검토 반영.

## 목표

전국 첫 신규 협회(KATO) 대회 수집을 붙이면서, **협회 등급체계를 유지·검증 가능하고 고객에게 제공 가능한 지식베이스(KB)로 관리하는 패턴**을 KATO 하나로 확립한다. P5a에서 만든 `mapDivisionsByDict`(DB 사전 매핑)의 첫 실사용.

## 구성 (한 PR, 현재 P5 브랜치에 이어붙임)

세 조각이 맞물린다: ① KB 패턴 → ② seed → ③ 파서.

### ① 등급체계 KB 패턴 (신규, KATO로 확립)

**"병렬 관리 + 검증" 아키텍처 — JSON 정본, HTML·seed는 뷰, CI가 일치 강제.**

- `docs/kb/grades/kato.divisions.json` — **기계 판독 정본**. 부서 배열, 각 원소:
  `{ code, org_code, label_ko, synonyms[], skill_tier, gender, age_min, champion_only, event_type, equiv_group }`. 협회가 체계를 바꾸면 여기를 수정.
- `docs/kb/grades/kato.html` — **고객용 안내**. 손으로 쓴 서술(KATO 개요·6단계 그룹체계·부서별 자격·승급규칙 — 연구문서 §1.2에서) + `<script>`가 `kato.divisions.json`을 `fetch`해 부서표를 렌더(기계 데이터 중복 없음 → 드리프트원 없음). 나중에 GitHub Pages/앱 웹뷰로 서빙(법적문서 호스팅과 동일 패턴).
- **검증 테스트** `supabase/functions/tests/grade_kb_verify_test.ts` (기존 CI Deno 잡이 `deno test tests` 로 자동 실행, `--allow-read`로 `../../docs/kb/grades/` 읽음):
  - `kato.divisions.json`을 읽고, seed 마이그레이션 파일(아래 ②)을 텍스트로 읽어, **JSON의 각 부서가 seed에 code·synonyms·skill_tier·gender·event_type가 일치하게 존재**하는지 단언(문자열 presence 기반 — SQL 파싱 안 함, 비취약).
  - seed의 `kato_*` 행 수 == JSON 부서 수(양방향, 한쪽에만 있는 부서 없음).
  - JSON 내부 무결성: code 유일, org_code 전부 'kato', synonym이 다른 부서 on-page명의 substring이 아님(bare `혼합`·`퓨처스` 충돌 금지 규칙).
  → JSON이나 seed 중 하나만 바뀌면 CI 실패. 블로커 #3(복제 드리프트) 차단.

### ② KATO 부서 seed (마이그레이션)

- 신규 마이그 `087_seed_kato_divisions.sql` — `tennis_divisions`에 `kato_*` 10개 INSERT(전문가 검증). `on conflict do update`. **JSON(①)과 필드 일치**(검증이 강제).
- **부서 10개 (전문가 3인 검토, 위너스부는 2026 페이지 미확인이라 제외):**

| code | label_ko | synonyms | skill_tier | gender | age_min | champion_only | event_type | equiv_group |
|---|---|---|---|---|---|---|---|---|
| kato_gaenari | 개나리부 | 개나리부,개나리 | rookie | female | null | false | doubles | null |
| kato_gukhwa | 국화부 | 국화부,국화 | intermediate | mixed | 40 | false | doubles | null |
| kato_challenger | 챌린저부 | 챌린저부,챌린저,챌린져부,챌린져 | advanced | all | null | true | doubles | null |
| kato_masters | 마스터스부 | 마스터스부,마스터스,마스터즈부,마스터즈 | open | all | 55 | true | doubles | null |
| kato_veteran | 베테랑부 | 베테랑부,베테랑 | intermediate | all | 55 | false | doubles | null |
| kato_instructor | 지도자부 | 지도자부,지도자 | advanced | all | 40 | false | doubles | null |
| kato_mixed | 혼합복식부 | 혼합복식부,혼합복식 | null | mixed | null | false | mixed | null |
| kato_couple | 부부혼합부 | 부부혼합부,부부혼합 | null | mixed | null | false | couple | null |
| kato_futures_m | 남자퓨처스부 | 남자퓨처스부,남자퓨처스 | rookie | male | null | false | doubles | null |
| kato_futures_w | 여자퓨처스부 | 여자퓨처스부,여자퓨처스 | rookie | female | null | false | doubles | null |

**전문가 반영 원칙:**
- **synonyms 철자변형 필수** — 사이트 `마스터스/챌린저`, 연구문서 `마스터즈/챌린져` 둘 다(안 넣으면 라이브 매칭 실패).
- **충돌 방지** — bare `혼합`(혼합복식·부부혼합 둘 다), bare `퓨처스`(남/여 둘 다) 금지. 위 synonyms는 이미 disambiguated.
- **equiv_group 전부 null** — `expand_division_codes`(P2, 라이브)가 equiv_group 동일성만으로 매칭(age/champion/gender 미검)하므로, 이름만 같고 자격 다른 협회 간 공유는 **실유저 오탐**. 협회 경계 공유는 이후 별도 패스(부부혼합→couple 등 안전 후보만).
- 등급 정밀도는 현재 매칭에 영향 없음(kato 등록유저 0 + P2.5 미구현 + draft 검수 + 카드는 label_local 원문) → 지금 중요한 건 `code`(안정·유일)와 `synonyms`(실제 on-page 문자열 매칭). 등급은 refinable.

### ③ KATO 파서

- 신규 `supabase/functions/_shared/crawler/parsers/kato_openlist.ts` — `ParserFn` 계약(`fetchListing → parseListing → fetchDetail → upsertTournament`), P5a `loadDivisionDict(supabase,'kato')` + `mapDivisionsByDict` 사용.
- registry `_shared/crawler/registry.ts`에 `'kato-openlist': katoOpenListParser` 추가.
- crawl_sources row(마이그 또는 execute_sql): slug `tennis-kato`, org_code `kato`, region_code null, parser_module `kato-openlist`, url `https://kato.kr/openList`, **enabled=false 초기**(라이브 검증 후 활성화).

**파싱 규약 (실측, resume 문서 부록):**
- 목록 `/openList`: 대회당 `<table>`(월별 `div.month-sector`). 제목 `a.content-title`, 날짜 `div.date`(`YYYY.MM.DD ~ YYYY.MM.DD` → start/end), 부서목록 `div.area > span.parts`, 상태 `td.part-sector .comgray|comblue|comdefault`(종료/접수중/준비중), 상세링크 `a[href^="/openGame/"]`.
- **종료(comgray) 대회는 상세 fetch·upsert 스킵**(노이즈·HTTP 절약). 접수중/준비중만 처리.
- 상세 `/openGame/{seq}`: `div.group-title`(제목), 라벨 td(`장 소`/`참가비`/`주 최` — 전각공백)→다음 td 값. 준비중 대회 `.` placeholder는 "데이터 없음".
- 부서: `mapDivisionsByDict(부서텍스트, katoDict)` → eligible_grades(kato_* codes)·division_label_local(원문). 미매칭 시 codes=[](결정 A).
- `application_deadline`: **null**(KATO 미제공). `host_orgs`: 파서 미설정(gnuboard와 동일, org는 org_code). start_date는 목록 날짜범위 시작.
- rate limit: gnuboard처럼 상세 fetch 상한(예 `slice(0,30)`).

## 성공 기준 (검증)

1. **KB 검증 CI**: `grade_kb_verify_test.ts`가 JSON↔seed 일치·JSON 무결성 통과. JSON이나 seed 한쪽만 바꾸면 실패함을 확인(테스트 자체가 그 대조를 함).
2. **seed 적용**: 마이그 087 execute_sql 적용 → `tennis_divisions`에 kato_* 10행, `mapDivisionsByDict('개나리부 국화부', katoDict)` == `{gaenari,gukhwa}` 확인.
3. **파서 단위**: `parseListing`/상세 필드 추출 단위 테스트(저장한 kato_openList/detail HTML 픽스처 또는 인라인 fixture로) `deno test`.
4. **라이브 크롤(배포 후, 컨트롤러)**: crawl_sources에 tennis-kato 등록·enable → force 크롤 → KATO 대회가 draft로 수집되고 eligible_grades가 kato_* 코드, division_label_local 원문 확인. **P5a 신규-org 라이브 검증 겸함.**

## 파일
- 신규: `docs/kb/grades/kato.divisions.json`, `docs/kb/grades/kato.html`, `supabase/functions/tests/grade_kb_verify_test.ts`, `supabase/migrations/087_seed_kato_divisions.sql`, `supabase/functions/_shared/crawler/parsers/kato_openlist.ts`
- 수정: `supabase/functions/_shared/crawler/registry.ts`
- 배포: `crawl-dispatch`(P5a·P5b 파서 번들)

## 범위 밖
- KATO 외 협회 KB 항목(KTA·KATA·KTFS·gj/jn·17시도) → 이후 점진 추가(패턴만 확립).
- equiv_group 협회 간 공유 → 별도 패스(부부혼합→couple 등, `expand_division_codes` 가드 개선과 함께).
- KB HTML의 앱 내 서빙/라우팅(고객 노출) → 이후. 지금은 정적 파일 + 검증까지.
- 지도자부 자격증 요건 등 스키마 미표현 항목 → 등급 스키마 확장은 별도.

## 리스크
- 파서는 실 외부 사이트 의존 — HTML 구조 변경 시 깨질 수 있음(기존 raw 보관·파싱가드 패턴 활용). 초기 enabled=false로 라이브 확인 후 활성화.
- 검증 테스트가 seed SQL을 텍스트 presence로 대조 → 포맷 자유롭되 code/synonym 문자열은 정확히 있어야 함(취약도 낮음).
- KATO 등급 매핑 LOW-CONFIDENCE 다수(전문가 플래그) — 현재 매칭 무영향, draft·후속 보정 가능. 국화부 gender는 문서 모순 있어 kato.kr 규정 재확인 권장(비차단).
