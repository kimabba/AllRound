# P5a — DB 기반 범용 부서 해석기 (설계 진행중 · resume 문서)

작성 2026-07-11 · **상태: 브레인스토밍 마무리 직전에 세션 중단. 맥미니에서 이어감.**
관련: `docs/team/REVIEW-nationwide-tennis-crawl.md`(로드맵 P5, 블로커 #3), P4(크롤러 일반화 완료).

> ⚠️ 이 문서는 **미확정 결정 1개**를 포함한다(§결정). 맥미니 세션은 그 결정을 사용자에게 최종 확인한 뒤 writing-plans로 진행할 것.

## 로드맵 상 위치

전국확장 P1~P4 완료(스키마·매칭·enum탈출·크롤러 slug제거). P5 = 파서 롤아웃 시작. **P5를 둘로 쪼갬(사용자 승인):**
- **P5a (이 문서)**: DB 기반 범용 부서 해석기 = 근본책. 블로커 #3(부서정보 3중 하드코딩) 해소.
- **P5b (다음)**: KATO 부서 seed + KATO 파서. 조사 완료 — §부록 KATO 참고.

**왜 근본책 먼저:** 앞으로 파서를 ~12개 붙인다(KATO→KTA→KSTF→경기→전북→…). 협회마다 하드코딩 해석기를 새로 짜면 블로커 #3가 12배 악화. 대신 크롤 시점에 `tennis_divisions.synonyms`를 org별로 읽는 **범용 해석기 하나**를 만들면, 새 협회 = **사전에 부서만 seed → 코드 안 짬**. (altitude: 올바른 깊이에서 일반화)

## P5a 설계

**순수 코드 변경(마이그레이션 없음, P4와 동일 성격). 파서는 이미 `ctx.audit.supabase`로 DB 접근 가능 — 조사로 확인.**

1. **범용 해석기** (순수 함수, 테스트 용이):
   `mapDivisionsByDict(text: string, dict: DivisionDictRow[]): { codes: string[]; label: string; unmapped: boolean }`
   - `dict` = 해당 org의 `tennis_divisions` 행: `{ code, synonyms: string[], label_ko }`.
   - 각 행의 synonym 중 하나라도 `text`에 substring으로 있으면 그 `code`+`label_ko` 채택.
   - 하나도 안 맞으면 `unmapped=true`, `codes=[]`.
   - **순서 주의**: 기존 `extractSidoStdDivisions`는 KEYWORD_MAP 배열 순서로 코드 순서가 정해졌고 테스트가 순서를 단언. 범용 해석기는 DB 행 순서라 순서가 달라질 수 있음 → **테스트를 집합 동치(정렬/포함)로 갱신**. eligible_grades는 `&&`(배열 겹침)이라 순서 무관 → 기능 영향 없음.

2. **사전 로딩** — 파서 진입 시 `ctx.audit.supabase.from('tennis_divisions').select('code, synonyms, label_ko').eq('org_code', source.org_code).eq('is_active', true)` 를 **1회** 조회해 dict 캐시. detail마다 재조회 금지.

3. **gj/jn 이관** — `gnuboard_sub5_5_contest.ts`가 `extractSidoStdDivisions(text, org)`(하드코딩) 대신 `mapDivisionsByDict(text, dict)` 사용. `_shared/crawler.ts`의 `extractSidoStdDivisions` KEYWORD_MAP **하드코딩 제거**(함수 삭제 또는 범용 래퍼로 축소). P1 시드 synonyms가 KEYWORD_MAP과 일치하도록 되어 있어 gj/jn 동작 보존됨(확인: gj_m_gold synonyms {골드부,골드} == KEYWORD_MAP).

4. **unmapped 처리** — 원문을 `division_label_local`에 저장. 모든 크롤은 이미 `status='draft'`(어드민 승인 후 게시)라 **미매칭은 draft 검수에서 자연 포착**(설계문서 §3-D "draft 플로우와 자연 결합"). 별도 unmapped 컬럼/큐는 P5+ (지금 불필요 — 기존 필드로 충분).

## 결정 (⚠️ 미확정 — 맥미니에서 최종 확인)

**부서가 사전과 하나도 안 맞을 때 `eligible_grades`를?**
- **권고 = A: 비움(`[]`) + draft 검수.** 원문은 `division_label_local`. 어드민이 게시 전 부서 보정. "추측 안 함" 원칙 + draft 흐름과 정합. 잘못 게시돼도 둘러보기엔 뜨고 등급매칭만 안 됨(저위험).
- 대안 B: 전등급 노출(야간플랜 제안) — 과노출/오탐. draft 검수가 이미 안전망이라 B의 이점 없음, 노이즈만 증가.
- 사용자는 시나리오 설명까지 들었고 세션 중단. **A로 확정할지 한 번 더 확인 필요.**

## 성공 기준 (검증)

1. `deno test`: `mapDivisionsByDict` 단위(mock dict) — 매칭/복수매칭/unmapped/임의 org prefix.
2. gj/jn 동치: 기존 extractSidoStdDivisions 테스트 케이스가 DB dict 기반으로도 같은 codes 집합 산출(순서 무관 단언으로 갱신).
3. 배포 후 라이브 스모크: tennis-gwangju/jeonnam 강제 크롤 → 여전히 gj_*/jn_* 코드(동작 보존).

## 범위 밖
- KATO seed·파서 → P5b.
- 어드민 미매칭 검수 **UI/큐** → 이후(플래그·draft 흐름으로 충분).
- enums.ts/Dart의 부서 하드코딩(블로커 #3의 클라 측) → P7 클라이언트 카탈로그화.

---

## 부록 — P5b KATO 사이트 조사 결과 (재조사 방지용, 2026-07-11 실측)

**사이트**: https://www.kato.kr/ · 목록 `https://kato.kr/openList` (www→apex 301). 서버렌더, **UTF-8**(EUC-KR 아님), PHP 7.4.

### 목록 `/openList`
- 당해년도 전체를 **1페이지**에 표시(~32개), 페이지네이션 없음. 연도는 **경로 세그먼트** `/openList/2025`, `/openList/2026`.
- 과거(종료)·현재(접수중)·예정(준비중) 혼재.
- 반복 단위 = 대회당 `<table>` 1개(월별 `div.month-sector` > `div.content-sector` 아래). 카드 구조:
  - 제목: `td.title-sector > div.title > a.content-title`
  - 날짜: `div.date`, 형식 `YYYY.MM.DD ~ YYYY.MM.DD`
  - **부서목록**: `div.area > span.parts` (쉼표구분 한글 부서명) — ⚠️ class명이 'area'지만 실제론 장소 아님, **부서 리스트**
  - 상태: `td.part-sector > div.each > a > span` — `span.comgray`=대회종료 / `span.comblue`=대회접수중 / `span.comdefault`=대회준비중. (닫힘일 때만 `div.ribbon.bg-close` "종료" 추가 존재)
  - 상세링크: `a[href^="/openGame/"]`, 예 `/openGame/0271` (4자리 zero-pad seq)
- 보너스: 페이지에 FullCalendar `events:[...]` JS 배열(2019~2026 전 대회 seq+날짜+상태색) 임베드 → 전연도 seq 열거에 활용 가능(상세 없음).

### 상세 `/openGame/{seq}` (서버렌더)
- `#tab1`(대회요강) 안 `<table class="table-bordered">`의 label/value `<tr><td>라벨</td><td colspan>값</td></tr>`. 라벨에 전각 공백(`장 소`,`주 최`). **셀렉터: 라벨 텍스트 일치 td → 다음 td 값.**
  - 대회명: `div.competition-title > div.group-title`
  - 랭킹그룹: `div.competition-group` (예 "2026 KATO랭킹 3그룹")
  - 부서별 일시: `일 시` rowspan 블록 안 `td.first-comp/rowcell`=부서명, 옆 td=날짜시각(예 "2026년 05월 06일 (수) 09:00")
  - 장소: `장 소` → 다음 td. (부서별 장소는 `#tab2 > td.rightnone > div.place`)
  - 참가비: `참가비` → 다음 td (예 "개인복식 팀당 64,000원 ...")
  - 주최: `주 최` → 다음 td / 주관: `주 관` → 다음 td
  - **신청기간: 명시적 날짜범위 없음.** 등록상태는 `#tab2`에 부서별 버튼(`span.takepartin`=참가신청 open / `span.takeready.no-action`=접수마감)+정원 "64 / 120". → `application_deadline`는 KATO에서 null 처리 유력.
- **준비중(준비중)** 대회는 값 셀이 리터럴 `.` placeholder + `#tab2` 비어있음 → 파서는 `.`을 "데이터 없음"으로 취급.

### KATO 부서 어휘 (실측 + 연구문서, 새 체계 — sido_std 아님)
목록/상세에서 관측: 혼합복식부, 챌린저부, 지도자부, 베테랑부, 마스터스부, 국화부, 개나리부, 부부혼합부, 여자퓨처스부, 남자퓨처스부.
연구문서(`docs/research/tennis-grade-systems.md` §1.2) 자격:
- 마스터즈부: 만55+ 우승자(open, age_min 55, champion)
- 챌린저부: 마스터즈/베테랑 1회우승(advanced, champion)
- 베테랑부: 만55+(intermediate/senior, age 55)
- 지도자부: 만40+ 지도자(advanced, age 40)
- 위너스부: 우승자(advanced, champion) — 사이트엔 '위너스부' 대신 다른 명칭 관측되니 seed 시 재확인
- 국화부: 만40+ 혼합(여성 우승계열 advanced, '국화'는 gj/jn w_winner synonym)
- 개나리부: 비우승자(rookie, 여성, '개나리'는 gj/jn w_rookie synonym)
- 퓨처스부(남/여): entry/rookie 계열 추정
- 혼합복식부/부부혼합부: mixed/couple event_type
→ **P5b에서 kato_* 코드로 seed** (skill_tier/gender/age_min/champion_only/event_type/equiv_group). '국화'·'개나리'는 gj/jn과 equiv_group 공유 검토(w_winner/w_rookie).

### KATO 파서 계약(기존 ParserFn 따름)
- `ParserFn = (source, ctx) => CrawlResult`. `fetchListing→parseListing→fetchDetail→upsertTournament`.
- registry(`_shared/crawler/registry.ts`)에 `'kato-openlist': katoParser` 추가.
- crawl_sources row: slug 'tennis-kato', org_code='kato', parser_module='kato-openlist', url='https://kato.kr/openList', enabled(초기 draft 검증 후).
- `CrawlerTournament`: eligible_grades(kato_* codes, P5a 해석기로), division_label_local(원문), start/end_date, location, entry_fee, organizer, host_orgs=['kato'] 등.
- 조사 샘플 HTML(세션 scratchpad, 비커밋): kato_openList.html, kato_detail_0289.html(접수중), kato_detail_0303.html(준비중). 필요시 재fetch.
