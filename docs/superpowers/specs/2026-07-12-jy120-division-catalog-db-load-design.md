# JY-120 — 앱 부서 카탈로그 DB 로드 전환 (kato_* 포함)

작성 2026-07-12 · Linear JY-120 · 관련: PR #206(P5 KATO), P5a `mapDivisionsByDict`, 메모리 `nationwide-tennis-schema`.

## 목표

Flutter 앱의 부서 라벨·필터가 정적 상수 `tennisDivisions`(gj/jn/kata/kstf/kta/ktfs/local, **kato 누락**) 대신 **DB `tennis_divisions`를 단일 진실**로 삼게 한다. KATO 대회가 published 되기 전에, 상세 칩·부서 필터·온보딩 부서선택이 `kato_*` 코드에 대해 올바른 한글 라벨을 표시하도록 한다.

크롤러(P5a)는 이미 `tennis_divisions`를 DB에서 읽는다. 앱만 정적 카탈로그에 머물러 있어 협회 추가마다 앱 재배포가 필요하고, kato_* 코드가 원문(`kato_gaenari`)으로 노출되는 문제가 있다.

## 현재 문제 (kato 기준 영향 3곳)

`tennisOrgs` const에는 `kato`가 이미 포함(온보딩에서 선택 가능)되지만 `tennisDivisions`에는 kato 부서가 0개다. 결과:

1. **상세 칩** `tournament_detail_screen.dart:247` `divisionLabel(g)` → `kato_gaenari` 원문 노출
2. **온보딩** `onboarding_screen.dart:1003` KATO 선택 시 부서 목록 비어 있음
3. **대회 필터** `tournaments_screen.dart` `tennisDivisionLabelsForOrg('kato')` → 부서 칩 없음

## 접근 (확정)

**런타임 DB 로드 + 인메모리 캐시. 기존 동기 API 유지.**

- 다른 후보: (a) 정적 `tennisDivisions`에 kato_* 하드코딩 → JSON·SQL·Dart **3중 사본**(드리프트, KB 패턴과 상충)으로 배제, (b) 빌드타임 코드젠 → 오늘 JSON은 kato만 존재·CI 재생성 스텝 필요로 배제.
- 선택 이유: DB-단일-진실 방향 일치, 신규 협회 = DB INSERT만으로 앱 반영(재배포 불요). 동기 build 호출처가 많아(온보딩·필터·상세·제출) riverpod 네이티브 전환 대신 전역 캐시 위임으로 blast radius 최소화.

## 아키텍처

```
DivisionCatalog (전역 싱글턴, plain Dart — grade_labels.dart 또는 인접 파일)
  - _byCode: Map<String, TennisDivision>?   (null = 미로드 → const fallback)
  - load(SupabaseClient): tennis_divisions SELECT → _byCode 완전 교체(멱등)
  - byCode(code), all(), forOrg(org)  → _byCode ?? const tennisDivisions

기존 top-level 함수 → DivisionCatalog 위임 (호출처 무변경):
  divisionLabel, tennisDivisions(게터화), divisionsForOrg,
  tennisDivisionLabels, tennisDivisionLabelsForOrg,
  tennisCodesForLabel, tennisCodesForLabels,
  tennisCodesForLabelInOrg, tennisCodesForLabelsInOrg,
  formatEligibleGrades

로드 트리거: main.dart onAuthStateChange(signedIn) + 초기 세션
  → DivisionCatalog.instance.load(client)   (initNotifications 와 동일 지점)
  RLS(tennis_divisions_read = authenticated) 이므로 인증 후에만 가능.
```

- **const `tennisDivisions` 유지** — 미로드/실패/오프라인/미인증 fallback. 제거하지 않음.
- **병합 안 함**: load 성공 시 `_byCode`를 DB 결과로 **완전 교체**(const와 섞지 않음). 조회는 "`_byCode` 있으면 DB, 없으면 const" — 둘 중 하나만.

## 데이터 흐름 & 모델 매핑

로드 쿼리:
```dart
supabase.from('tennis_divisions')
  .select('code, org_code, label_ko, gender')
  .eq('is_active', true)
  .order('code')
```

DB row → `TennisDivision`:

| DB | Dart | 비고 |
|---|---|---|
| `code` | `code` | |
| `org_code` | `org` | |
| `label_ko` | `label` | 칩/필터 표시명 |
| `gender` | `gender` | |
| — | `hasRanking` | DB 없음 → 기본 `false`. **죽은 필드**(앱 내 사용처 0, grep 확인) |

`synonyms/skill_tier/age_min/champion_only/event_type/equiv_group`은 앱 표시에 불필요 → SELECT 제외(YAGNI).

**정렬**: 필터 칩 순서는 `tennisDivisionLabels()`의 "첫 등장 순서 보존"에 의존한다. DB `order('code')`만으로는 협회 그룹핑이 흐트러진다. → 로드 후 **org 우선순위 배열**(`gj, jn, kta, kato, kata, ktfs, kstf, local`)로 2차 정렬해 기존 UX 순서를 보존한다. (org 우선순위 배열은 `tennisOrgs` const 순서 재사용 가능)

조회(동기, UI build 그대로):
```
divisionLabel(code) → catalog.byCode(code)?.label ?? gradeLabels[code] ?? code
tennisDivisions     → catalog.all()   (로드됐으면 DB, 아니면 const)
```

## 에러 처리 & 엣지케이스

- **로드 실패**(네트워크/타임아웃/RLS): 예외 삼키고 fallback 유지, 앱 진입 차단 안 함. 다음 앱 시작 시 재시도.
- **미인증**: 트리거가 signedIn/초기세션이라 인증 전 로드 안 함. 로그인 전 화면은 const fallback으로 충분.
- **로드 실패 시 kato_***: 칩만 원문 노출 — 현 상태와 동일(회귀 아님).
- **재로그인/계정 전환**: load 재호출로 캐시 갱신(멱등).

## 테스트

- **DivisionCatalog 단위**: (1) 미로드 시 const fallback, (2) load 후 kato_* 라벨 해석, (3) load 실패 시 fallback 유지, (4) org 우선순위 정렬. Supabase는 fake/주입.
- **위임 함수**: `divisionLabel('kato_gaenari')` 로드 후 '개나리부', 미로드 시 원문.
- **회귀**: gj/jn 라벨·필터 동작 불변(fallback·DB 양쪽).
- `flutter test` + `flutter analyze`(CI). 위젯 테스트는 과함 → 카탈로그 로직 단위 중심.

## 파일

- 수정: `app/lib/utils/grade_labels.dart` — `DivisionCatalog` 추가, top-level 함수 위임 전환, `tennisDivisions` const는 fallback으로 유지(게터/명명 조정)
- 수정: `app/lib/main.dart` — onAuthStateChange(signedIn)·초기 세션에서 `DivisionCatalog.instance.load(client)` 호출
- 별도 서비스 파일 없음 — 쿼리 1개라 `DivisionCatalog.load(SupabaseClient)`가 직접 수행
- 수정 테스트: `app/test/grade_labels_test.dart`(기존 파일) — DivisionCatalog 로드/fallback/정렬 케이스 추가

## 범위 밖 (YAGNI)

- 정적 `tennisDivisions` 완전 제거(fallback 유지)
- regions·orgs 카탈로그 DB화(별도)
- 실시간 구독/갱신, riverpod 네이티브 전환
- KATO 라이브 활성화(별도 — seed 적용·enable·크롤)

## 성공 기준

1. DB 로드 후 `divisionLabel('kato_gaenari')` == '개나리부', 상세 칩·온보딩·필터가 kato_* 정상 표시
2. 로드 실패/오프라인에도 기존 gj/jn 동작 불변(fallback)
3. `flutter analyze`(warning 0)·`flutter test` 통과
4. 신규 협회 부서 추가가 DB INSERT만으로 앱에 반영(재배포 불요)됨을 카탈로그 단위 테스트로 확인
