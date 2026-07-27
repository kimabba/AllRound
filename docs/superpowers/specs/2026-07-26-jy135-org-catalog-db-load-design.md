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
  **`not null default 1000`** — 백과장이 값을 안 정해도 INSERT 가 되고, 지정 안 한 행은 끝으로 모인다.
- 정렬 계약: **`order by sort_order, name_ko, code`**. 동률에서 비결정 정렬이 되지 않도록 tiebreak 을 명시한다.
- `label_ko` 가 null 이면 `name_ko` 로 폴백한다(카탈로그에 규칙 고정). 백과장 INSERT 규칙은
  **"`label_ko`·`short_label` 은 화면에 보일 문자열 그대로"** 한 줄로 문서화한다.

> 페이블 반대 의견(기록): `sort_order` 없이 `org_type`+name_ko+code 로 자동 배치하면 백과장이
> 순서값을 산정할 필요가 없다. 채택하지 않은 이유 — 현재 앱 순서(kta→kato→kata→ktfs→kstf→
> kssta→kasta→gj→jn→local)는 **가나다순이 아니라 큐레이션된 순서**라, 자동 정렬로 바꾸면
> 사용자 화면의 협회 나열이 바뀐다. `default 1000` + tiebreak 으로 "값을 안 정해도 INSERT 가능"
> 이라는 반대 측 이점은 확보한다.
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

`tournaments-search`(읽기·빈번)와 `chat` 라벨은 **이번 범위 밖**. TS `TENNIS_ORGS` 상수는 그
두 경로를 위해 유지한다.

> **⚠ 후속 선행 조건(페이블 지적)**: `tournaments-search/index.ts:45` 도 `isValidTennisOrg` 로
> **검증**해 `invalid org` 를 반환한다(실측 확인). 즉 TS 목록이 남아 있는 동안 새 협회의
> 필터 칩을 누르면 **결과 0건이 아니라 에러**다. 따라서 `tournaments-search` 의 DB 전환은
> **15개 실데이터 추가 전 필수 선행**이다. 후속 이슈에 이 조건을 명시한다.
> (최초 스펙은 "검색은 0건이라 무해" 로 잘못 적었다 — 검증 축인 것을 확인하고 정정.)

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

## 구현 시 판단 남긴 것

`OrgCatalog` 를 별도 싱글턴으로 둘지, 기존 `DivisionCatalog` 에 org 로드를 얹을지는 구현 단계
판단이다. 별도 싱글턴은 경계가 깨끗하고 테스트가 격리되지만 생명주기 기계장치(`whenReady`·
`reset`·세대 카운터) 사본과 `main.dart` 배선 3곳이 늘어난다(페이블 지적 — 숨은 비용). 확장은
diff 가 작지만 한 싱글턴이 두 도메인을 갖는다. **기본은 별도 싱글턴**으로 가되, 구현하며
중복이 실제로 크면 확장으로 바꾼다.

## 후속 (별도 이슈)

- **`tournaments-search` org 검증의 DB 전환 — 15개 실데이터 추가 전 필수 선행**(위 ⚠ 참조).
  안 하면 새 협회 필터 칩이 `invalid org` 에러를 낸다.
- `chat` 협회 라벨의 DB 전환(우선순위 낮음 — 깨져도 코드 노출 수준).
- 15개 시도협회 실데이터 + 부서 체계(백과장 선행).
