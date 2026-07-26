# JY-135 협회 카탈로그 DB 로드 전환 (Option A — 구조 배관)

> 작성 2026-07-26 (드론). 설계 검토: codex(조건부 승인). 선례: `2026-07-12-jy120-division-catalog-db-load-design.md`.

## 목표

테니스 협회 목록·라벨의 정본을 Dart 하드코딩에서 **DB `public.tennis_orgs`** 로 옮긴다.
백과장이 협회를 추가할 때 **행 INSERT 하나**로 앱에 반영되게 하는 것이 목적이다.

**범위 밖**: 15개 시도협회 실데이터 추가(백과장 선행 필수, JY-135 본체).

## 왜 지금 / 왜 이 방식

부서(division)는 JY-120 에서 이미 DB 로드로 전환됐다(`DivisionCatalog`). 협회만 하드코딩으로
남아 3중 동기화(Dart·TS·죽은 SQL enum) 부담이 있다. 검증된 패턴이 같은 파일에 있으므로
복제 위험이 낮다.

## 실측 근거 (2026-07-26, 운영 `bsjdgwmveokanclqwtvx`)

| 사실 | 근거 |
|---|---|
| 협회 추가 = 행 INSERT. PG enum 아님 | `drop type public.tennis_org` (20260711002939:107). FK 3개가 `tennis_orgs(code)` 참조: `user_tennis_orgs.org`·`crawl_sources.org_code`·`tennis_divisions.org_code` |
| `tennis_orgs` 컬럼 | code·name_ko·short_label(nullable)·org_type·region_code·division_scheme·is_active·created_at. **`sort_order` 없음** |
| **라벨 불일치** | 앱 `광주협회`/`전남협회`/`시·군/클럽` vs DB `GJTA`/`JNTA`/`null`. 앱 `대한테니스협회 (KTA)` vs DB `대한테니스협회` |
| RLS | `tennis_orgs_read` = `auth.role()='authenticated'`. 쓰기 `is_admin()` |
| 비활성 협회 보유자 | **0명**(ktfs). 실사용 org = gj·kata·kta |
| 서버 검증 구멍 | `tournaments-submit/index.ts:271` 이 정적 `isValidTennisOrg` 로 검증 → DB 에 협회를 넣어도 **제보가 거절된다** |
| 죽은 게이트 | `check_enums.py:179-182` 가 **삭제된** SQL enum 텍스트를 Dart/TS 와 3층 비교 |
| 두 번째 하드코딩 | `tournament_submit_screen.dart:143-151` `_tennisOrgOptions`(7개만, 자체 라벨) |
| 미사용 심볼 | Dart `isValidTennisOrg`(grade_labels.dart:564) 호출부 0건 |

## 설계

### 1. 마이그레이션 — 표시 정본을 DB 로

- `tennis_orgs` 에 `label_ko` text, `sort_order` int 추가.
- 백필: **현재 앱 문자열 그대로**. `label_ko` = `대한테니스협회 (KTA)` 등, `short_label`
  덮어쓰기(`GJTA`→`광주협회`, `JNTA`→`전남협회`, `local` null→`시·군/클럽`).
  백필을 빼면 사용자 화면 문구가 바뀌고 `local` 은 코드가 노출된다.
- `sort_order` 는 현재 Dart 배열 순서를 간격(10,20,…)으로 부여한다. 15개 추가 시 사이에 끼울 수 있다.
- 정렬 계약: `order by sort_order, code`. `org_type`+code 조합은 결정적이지만 사용자에게 의미 있는
  순서(전국→지역→기타)를 보장하지 못한다.
- **RLS 는 건드리지 않는다.** 로그인 전 소비처가 없고(`main.dart:56-57` 이 세션 존재 시에만 로드),
  부서·등급도 같은 정책이다. 소비처 없이 권한만 넓히는 것은 최소권한 위반.

### 2. 앱 `OrgCatalog`

`DivisionCatalog` 를 그대로 복제한다: 싱글턴 · DB 로드 · const fallback · `whenReady` 스플래시
게이트 · `reset()` · load 세대 카운터 · `catalogRevision` 공유(리빌드 전파는 자동으로 따라온다).

- fallback = 현재 상수 그대로. DB 로드 실패 시 화면 문구가 그대로 유지된다.
- `is_active=false` 는 **선택지에서 제외**만 한다. 보유자 보존 로직은 넣지 않는다(대상 0명, YAGNI).
  라벨 조회는 활성 여부와 무관하게 동작해야 한다 — 비활성 협회를 이미 가진 사용자의 라벨이
  코드로 노출되면 안 된다.

### 3. 소비처 전환

순서 의존 3곳: `grade_labels.dart:418`(부서 그룹 순서) · `tournaments_screen.dart:1893`(협회 필터 칩)
· `onboarding_screen.dart:320`(온보딩 선택지).
라벨 5곳: `onboarding_screen.dart:360,996` · `tournaments_screen.dart:1895,1945` ·
`profile_sports_widgets.dart:279,280` · `active_filters.dart:112`.
생명주기: `main.dart:58`(load) · `:64`(reset) · `:242`(whenReady) 에 나란히 연결.

`tournament_submit_screen.dart:143` 의 두 번째 목록도 카탈로그로 통합한다. 남기면 "행 하나로
앱 반영" 이 화면에 따라 거짓이 되고 협회 추가가 조용히 누락된다.

`isValidTennisOrg`(Dart) 는 호출부가 없으므로 삭제한다.

### 4. 서버 검증 — 제보 경로만 DB 로

`tournaments-submit` 의 org 검증을 정적 목록에서 **DB 조회**로 바꾼다(`tennis_orgs` 에 존재 +
`is_active`). 제보는 쓰기 경로라 빈도가 낮아 조회 1회 비용이 무의미하다.

`tournaments-search`(읽기·빈번)와 `chat` 라벨은 **이번 범위 밖**. 검색은 없는 협회를 넣어도
결과가 0건이라 무해하다. TS `TENNIS_ORGS` 상수는 그 두 경로를 위해 유지한다.

### 5. 게이트 정리

`check_enums.py` 의 `tennis orgs` 3층 비교에서 **죽은 SQL 축을 제거**한다. Dart 상수가 사라지므로
이 검사는 그대로 두면 깨지고, 되살리려면 가짜 enum 을 복원해야 한다. 등급이 JY-321 에서 실제 DB
조회로 옮겨간 것과 같은 방향이다.

## 테스트

- `OrgCatalog` 단위 테스트: `ingestRows` 로 fallback↔DB 교체, `sort_order` 정렬, `reset()` 후 fallback 복귀,
  비활성 제외 + 비활성 라벨 조회는 동작.
- `catalog_rebuild_test.dart` setUp 에 `OrgCatalog.reset()` 추가(누락 시 테스트 간 상태 누수).
- 기존 깨질 테스트 보정: `grade_labels_test.dart`(org 순서 기대), `active_filters_test.dart`(짧은 라벨).
- 마이그레이션: `supabase db reset` 후 백필 값이 현재 앱 문자열과 일치하는지 확인.
- Edge: `tournaments-submit` 의 DB 검증 경로 deno 테스트.

## 위험과 대응

| 위험 | 대응 |
|---|---|
| 백필 누락 → 화면 문구 변경·코드 노출 | 마이그레이션에서 현재 문자열 그대로 백필, 테스트로 고정 |
| DB 로드 실패 → 목록 빔 | const fallback 유지(DivisionCatalog 와 동일) |
| Edge 배포 누락 → 제보 검증 불일치 | 머지 후 `tournaments-submit` 수동 배포(CI 자동배포 없음) |
| 순서 정본 이원화 | `sort_order` 단일 정본, Dart 배열 순서 의존 제거 |

## 후속 (별도 이슈)

- 15개 시도협회 실데이터 + 부서 체계(백과장 선행).
- `tournaments-search` org 검증·`chat` 협회 라벨의 DB 전환.
