# 전국 테니스 대회 크롤 — 확장 설계 검토서

작성 2026-07-10 · Fable 에이전트 검토 3기(협회 카탈로그 / DB 스키마 / 등급체계) 종합.
관련: `docs/research/tennis-grade-systems.md`(기존 조사, 5/9), `docs/team/PLAN-local-nightly-crawl.md`(야간 파이프라인 — 이 검토가 데이터 모델을 재정의하므로 그 계획은 인프라 부분만 유효).

---

## 1. 데이터 소스 현황 (조사 결과)

크롤 가능 **약 19곳**, 신규 파서 **12~14종**이면 전량 커버.

### 구조별 그룹 → 파서 소요

| 구조 | 소스 | 파서 |
|---|---|---|
| A. gnuboard 커스텀스킨 | 광주, 전남 | **0 (보유)** |
| B. 표준 gnuboard board.php | 전북(GB5), 경기 kgtfs(GB4·EUC-KR) | 1종 + 인코딩변형 |
| C. Java .do | **KTO(KATO)**, **KTA**, 경남 | 3종 (서버렌더라 난도 낮음) |
| D. Classic ASP | KATA(ikata), 강원 | 2~3종 (ikata는 POST 페이징) |
| E-1. 임대형 pg_idx PHP | KSTF, KSSTA | 1종 (동일 솔루션 → 2곳 커버) |
| E-2. 정적 HTML frameset(EUC-KR) | 인천, 울산(동일 템플릿), 부산 | 1~2종 |
| E-3. 모던 웹앱 | 서울(Blazor SSR), 제주(AJAX JSON), kata-tennis(Next.js) | 3종 |
| E-4. 커스텀 PHP | 대전 | 1종 |
| 제외 | 대구·세종·충북·충남·경북(사이트없음), KTFS(소멸→KTA흡수), KASTA(다음카페), ksfasta(준비중) | — |

### 우선순위 (권장)
1. **KATO `/openList`** — 전국 동호인 대회 최다(연 100+), 풀텍스트 서버렌더 → 최고 가성비
2. **KTA `cmptList.do`** — 대한테니스협회 공식
3. **KSTF/KSSTA** — 파서 1개로 시니어 2곳
4. **경기 kgtfs** — 기존 gnuboard 파서 변형(EUC-KR)
5. 전북 → 이후 정적HTML(인천·울산·부산) → .asp/모던웹앱

### 주의
- **EUC-KR**: 부산·인천·울산·경기 → `TextDecoder('euc-kr')` 분기 필수.
- **사이트 없는 5개 시도**: 시군구 사이트(천안·포항·창원 등)나 tennispeople.kr 매체 크롤이 대안.

---

## 2. 현재 스키마 — 전국 확장 블로커 4개

| # | 블로커 | 문제 |
|---|---|---|
| 1 | `tennis_org`가 **PG enum** (009) | 협회 추가 = DDL + TS/Dart 배포 + **앱 스토어 심사**. 수십~수백 협회 운영 불가 |
| 2 | `expand_gj_jn_codes()` 하드코딩 (072, RPC 6곳 복제) | 광주↔전남 치환이 SQL 코드에. + `LIKE 'gj_%'`의 `_`가 와일드카드라 잠재 버그(`gj2_` 등 오매칭) |
| 3 | DB / TypeScript / Dart **3중 수동 동기화** | `grade_labels.dart`가 `enums.ts`와 1:1 미러. 지역/협회/부서 셋 다 |
| 4 | 크롤러 `slug.includes('gwangju') ? 'gj' : 'jn'` (파서 420행) | **광주 아닌 새 소스는 전부 조용히 'jn'** — 3번째 소스 추가 즉시 사고 |

부수 발견:
- **지역 입도 불일치**: 광주/전남은 시도인데 seoul_metro·busan_ulsan_gn은 권역 → 17시도로 재정비 필요(기존 코드 FK 참조 중이라 삭제 불가, deprecate).
- `eligible_grades`/`division_codes`가 무결성 없는 `text[]` → 17개+에선 쓰레기 코드 누적.
- 이미 있으나 미활용: `tennis_tournament_details.division_kta_standard/gender/age_group`(059), `division_label_local`(크롤 원문 라벨) → 정규화 레이어 맹아.

---

## 3. 목표 설계

### 원칙
**"닫힌 집합은 enum, 운영 중 늘어나는 디렉터리는 테이블."** 협회·지역·부서 = 테이블. gender·entry_fee_unit·status 등 진짜 닫힌 집합 = enum 유지.

### 3-A. 지역 — 17 시도 테이블
- `regions`를 17 시도 표준 코드(seoul, busan, …, gyeonggi)로 재시드. 권역 표시는 `zone` 컬럼으로(권역을 별도 코드로 두지 말 것).
- 기존 8코드는 `is_active`/`superseded_by`로 deprecate(FK 참조). `tournaments.region`(한글)은 표시 전용 격하, 필터·조인은 `region_code` 일원화.

### 3-B. 협회 — enum → 테이블
- 신규 `tennis_orgs` 테이블: `code PK`(`_`금지), `name_ko`, `org_type(national|sido|sigungu|club)`, `region_code FK nullable`, `division_scheme`, `is_active`. 현행 10개 시드.
- `user_tennis_orgs.org`·`host_orgs tennis_org[]` → `text FK` 전환 + RPC 재생성(`NOTIFY pgrst`, overload 주의).
- 이후 신규 협회 = **INSERT 1줄 + 크롤소스 등록**. 앱 릴리스 불요.

### 3-C. 등급/부서 — 하이브리드 사전 모델
한국 동호인 부서는 **4축 분해**: 실력티어 × 성별 × 연령 × 종목형태 (+ 자격플래그: 선수출신·우승이력). 명칭은 제각각이나 사다리 구조는 전국 공통.

- 신규 `tennis_divisions`(또는 `division_dictionary`): `code PK`, `org_code FK`, `label_ko`, `synonyms[]`, **`skill_tier`**(rookie<intermediate<advanced<open), `gender`, `age_min`, `champion_only`, `event_type`, **`equiv_group`**. 현행 69개 시드, gj/jn 동일 suffix는 같은 equiv_group.
- **사용자는 범용 좌표 1회 등록**(skill_tier, gender, birth_year, player_origin — PLAYER_ORIGINS 이미 존재). 기존 `division_codes`는 "협회 검증 부서" 오버라이드 레이어로 유지.
- **매칭**: 대회 부서 → 사전으로 canonical 변환 → ① 사용자가 그 org 등록부서 있으면 코드 직매칭(현행 정확도) → ② 없으면 skill_tier ≤ + 성별/연령 필터. `expand_gj_jn_codes` 폐기(광주↔전남은 "같은 equiv_group"으로 자연 해소, 타 권역도 하드코딩 없이 확장).
- 티어 매칭은 **recall 우선**(놓치지 않기), 정밀 자격판정은 협회 몫(실제 신청·검증은 협회 사이트에서). 대회 카드엔 항상 `division_label_local` 원문 표기.

### 3-D. 크롤러 일반화
- `crawl_sources`에 `org_code`, `region_code` 컬럼 추가 → slug 추론(#4 블로커) 제거.
- `extractGJDivisions` org 파라미터 `'gj'|'jn'` → 일반 string. 미매칭 시 "오픈+일반 기본값"(조용한 오류) 대신 **원문 라벨 + `unmapped` 플래그 → 어드민 검수 큐**(draft 승인 플로우와 자연 결합). 어드민이 1회 매핑 → 사전에 동의어 추가 → 다음부터 자동. LLM 매핑은 큐 보조.

### 3-E. 클라이언트 카탈로그화
- 앱이 org/region/division을 서버에서 받아 캐시. Dart 하드코딩은 오프라인 폴백 격하. **이 단계 완료 전까진 신규 지역마다 앱 릴리스 필요** — 로드맵에 반영.

---

## 4. 구현 로드맵 (비파괴 → 파괴 순)

| P | 단계 | 내용 | 파괴성 |
|---|---|---|---|
| 1 | **스키마 기반** | `tennis_orgs`·`tennis_divisions`(사전) 테이블 생성 + 현행 시드, `regions` 17시도 추가(기존 deprecate), `crawl_sources.org_code/region_code` 추가 | 비파괴 |
| 2 | **매칭 일반화** | equiv_group/skill_tier 매칭 도입, `expand_gj_jn_codes`를 사전조회 래퍼로 재구현(시그니처 유지) + 와일드카드 버그 수정 | 저 |
| 3 | **enum 탈출** | `tennis_org` enum → text FK, RPC 재생성(NOTIFY pgrst) | 중 |
| 4 | **크롤러 일반화** | slug 추론 제거, 검수 큐, EUC-KR 디코딩 헬퍼 | 저 |
| 5 | **파서 롤아웃** | 우선순위대로: KATO → KTA → KSTF/KSSTA → 경기 → 전북 → 정적HTML → asp/웹앱 | — |
| 6 | **로컬 야간 + 포스터 AI** | `docs/team/PLAN-local-nightly-crawl.md` (Phase 3~5) | — |
| 7 | **클라이언트 카탈로그화** | 앱이 서버에서 목록 수신 | 중 |

---

## 5. 결정 필요 (사용자)

1. **범위**: 이번에 전국 설계(P1~4 스키마) 다 잡고 갈지, 아니면 **우선 KATO·KTA 두 곳만** 파서 붙여 데이터부터 확보하고 스키마는 점진적으로 갈지.
2. **등급 모델**: 하이브리드 사전(3-C) 채택 여부 — 이게 가장 큰 스키마 변경이자 확장성의 핵심.
3. **지역 재정비**: 8권역 → 17시도 재시드를 지금 할지(기존 데이터 백필 비용 있음).
4. **클라이언트 카탈로그화(3-E)**: 지금 할지(앱 릴리스 없이 지역/협회 추가 가능해짐) vs 나중.
5. **파서 구현 순서**: 우선순위(KATO 먼저) 동의 여부.

## 6. 리스크
- 5개 시도(대구·세종·충북·충남·경북) 데이터 공백 — 시군구/매체 크롤 대안 필요.
- .asp/모던웹앱(ikata·제주·서울)은 파서 난도 상 → 후순위.
- enum→text 전환은 RPC 시그니처 변경 → 앱 하위호환 세트로.
- EUC-KR 4곳 인코딩 사고 위험.
