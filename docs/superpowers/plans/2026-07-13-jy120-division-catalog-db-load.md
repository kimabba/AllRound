# JY-120 부서 카탈로그 DB 로드 전환 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 앱의 테니스 부서 라벨·필터를 정적 상수 대신 DB `tennis_divisions`에서 런타임 로드하여, KATO(`kato_*`) 부서가 상세 칩·온보딩·필터에서 올바른 한글 라벨로 표시되게 한다.

**Architecture:** `grade_labels.dart`에 전역 싱글턴 `DivisionCatalog`를 추가한다. 미로드 상태에서는 기존 `const` 부서 목록(fallback)을, 로드 성공 시 DB 결과를 반환한다. 기존 top-level 함수(`divisionLabel`, `tennisDivisions` 등)는 모두 이 카탈로그에 위임하므로 UI 호출처는 무변경이다. `main.dart`에서 인증(signedIn/initialSession) 시점에 `DivisionCatalog.instance.load(client)`를 호출한다.

**Tech Stack:** Flutter, `flutter_riverpod` ^2.6.1, `supabase_flutter`, `flutter_test`.

## Global Constraints

- Dart `dynamic` 지양 — DB row 매핑은 `Map<String, dynamic>` 인덱싱 후 명시적 캐스트(`as String`)로 처리.
- `flutter analyze` warning 0 (CI가 warning을 에러 처리).
- RLS `tennis_divisions_read = authenticated` — 로드는 인증 이후에만 호출.
- 로드 실패/미인증/오프라인 시 절대 앱 진입을 막지 않는다 (예외 삼키고 fallback 유지).
- `const` fallback 목록은 **제거하지 않는다**.
- 병합 금지: 로드 성공 시 카탈로그를 DB 결과로 **완전 교체**(const와 섞지 않음).
- Co-author 커밋 라인: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

### Task 1: DivisionCatalog 도입 + top-level 함수 위임 전환

**Files:**
- Modify: `app/lib/utils/grade_labels.dart:44-253`
- Test: `app/test/grade_labels_test.dart`

**Interfaces:**
- Consumes: 기존 `TennisDivision` 클래스(`app/lib/utils/grade_labels.dart:29-42`), `const tennisOrgs`(같은 파일 하단, org 우선순위 배열로 재사용), `gradeLabels` 맵.
- Produces:
  - `class DivisionCatalog` — 싱글턴. 시그니처:
    - `static final DivisionCatalog instance`
    - `bool get isLoaded`
    - `List<TennisDivision> get all`
    - `TennisDivision? byCode(String code)`
    - `Future<void> load(SupabaseClient client)`
    - `@visibleForTesting void ingestRows(List<Map<String, dynamic>> rows)`
    - `@visibleForTesting void reset()`
  - `List<TennisDivision> get tennisDivisions` — top-level 게터(기존 `const` 대체, 카탈로그 위임).
  - 기존 top-level 함수 시그니처는 전부 불변(내부만 게터/카탈로그 위임): `divisionLabel`, `divisionsForOrg`, `tennisDivisionLabels`, `tennisCodesForLabel`, `tennisCodesForLabels`, `tennisDivisionLabelsForOrg`, `tennisCodesForLabelInOrg`, `tennisCodesForLabelsInOrg`, `formatEligibleGrades`.

**배경 (구현자가 알아야 할 현재 코드):**
현재 `grade_labels.dart:44`는 `const tennisDivisions = <TennisDivision>[...]`(49개, gj/jn/kta/kata/ktfs/kstf/local, **kato 없음**)이고, `_divisionLabelMap`(line 181)이 이걸로 만들어지며, `divisionLabel`·`divisionsForOrg`·`tennisDivisionLabels`·`tennisCodesForLabel` 등이 `tennisDivisions`를 직접 순회한다. `tennisDivisions`를 게터로 바꾸고, `divisionLabel`은 `_divisionLabelMap` 대신 카탈로그를 쓰게 하는 것이 핵심.

- [ ] **Step 1: `import 'package:flutter/foundation.dart';`와 `import 'package:supabase_flutter/supabase_flutter.dart';` 추가**

`app/lib/utils/grade_labels.dart` 최상단(파일 1행 `enum Sport` 위)에 추가:

```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

- [ ] **Step 2: 실패하는 카탈로그 테스트 작성**

`app/test/grade_labels_test.dart`의 `import` 아래, `void main() {` 안 마지막 group 뒤에 새 group 추가. 파일 상단 import는 이미 `package:allround/utils/grade_labels.dart` 있음. `TennisDivision` 접근을 위해 추가 import 불필요(같은 파일에서 export됨).

```dart
  group('DivisionCatalog DB load', () {
    setUp(() => DivisionCatalog.instance.reset());
    tearDown(() => DivisionCatalog.instance.reset());

    test('미로드 시 all()은 const fallback 반환', () {
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      // fallback 에는 kato 부서가 없다
      expect(
        DivisionCatalog.instance.all.where((d) => d.org == 'kato'),
        isEmpty,
      );
    });

    test('미로드 시 divisionLabel(kato_*)은 코드 원문 반환', () {
      expect(divisionLabel('kato_gaenari'), 'kato_gaenari');
    });

    test('ingestRows 후 kato 라벨 해석', () {
      DivisionCatalog.instance.ingestRows([
        {
          'code': 'kato_gaenari',
          'org_code': 'kato',
          'label_ko': '개나리부',
          'gender': 'female',
        },
        {
          'code': 'kato_masters',
          'org_code': 'kato',
          'label_ko': '마스터스부',
          'gender': 'all',
        },
      ]);
      expect(DivisionCatalog.instance.isLoaded, isTrue);
      expect(divisionLabel('kato_gaenari'), '개나리부');
      expect(divisionLabel('kato_masters'), '마스터스부');
      // 로드 성공 시 완전 교체: fallback gj 부서는 더 이상 없음
      expect(DivisionCatalog.instance.all.where((d) => d.org == 'gj'), isEmpty);
      expect(tennisDivisionLabelsForOrg('kato'), ['개나리부', '마스터스부']);
    });

    test('ingestRows 는 org 우선순위(tennisOrgs 순서)로 그룹핑, 그룹 내 입력순 보존', () {
      // 입력을 뒤섞어 넣어도 kta < gj < kato 순서(tennisOrgs)로 그룹핑돼야 함
      DivisionCatalog.instance.ingestRows([
        {'code': 'gj_b', 'org_code': 'gj', 'label_ko': 'GJ-B', 'gender': 'all'},
        {'code': 'kato_a', 'org_code': 'kato', 'label_ko': 'KATO-A', 'gender': 'all'},
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
        {'code': 'gj_a', 'org_code': 'gj', 'label_ko': 'GJ-A', 'gender': 'all'},
      ]);
      final orgs = DivisionCatalog.instance.all.map((d) => d.org).toList();
      // tennisOrgs: kta 가 kato 보다, kato 가 gj 보다 앞
      expect(orgs, ['kta', 'kato', 'gj', 'gj']);
      // gj 그룹 내부는 입력 순서(gj_b, gj_a) 보존
      final gjCodes = DivisionCatalog.instance.all
          .where((d) => d.org == 'gj')
          .map((d) => d.code)
          .toList();
      expect(gjCodes, ['gj_b', 'gj_a']);
    });

    test('reset 후 다시 fallback 으로 복귀', () {
      DivisionCatalog.instance.ingestRows([
        {'code': 'kato_gaenari', 'org_code': 'kato', 'label_ko': '개나리부', 'gender': 'female'},
      ]);
      expect(DivisionCatalog.instance.isLoaded, isTrue);
      DivisionCatalog.instance.reset();
      expect(DivisionCatalog.instance.isLoaded, isFalse);
      expect(divisionLabel('kato_gaenari'), 'kato_gaenari');
    });
  });
```

- [ ] **Step 3: 테스트 실행해 실패 확인**

```bash
cd app && flutter test test/grade_labels_test.dart
```
Expected: FAIL — `DivisionCatalog` 미정의(compile error) 및 `ingestRows` 미존재.

- [ ] **Step 4: `const tennisDivisions`를 `const _kFallbackDivisions`로 리네임**

`app/lib/utils/grade_labels.dart:44`의 선언부만 변경(내용 49개 항목은 그대로):

```dart
const _kFallbackDivisions = <TennisDivision>[
```

(나머지 `TennisDivision(...)` 리스트 본문과 닫는 `];`는 변경 없음.)

- [ ] **Step 5: `_divisionLabelMap`(line 181-183) 제거하고 그 자리에 DivisionCatalog + 게터 추가**

`app/lib/utils/grade_labels.dart`에서 기존:

```dart
final _divisionLabelMap = <String, String>{
  for (final d in tennisDivisions) d.code: d.label,
};

/// division 코드 → 표시명 (미등록 코드는 코드 그대로 반환)
String divisionLabel(String code) =>
    _divisionLabelMap[code] ?? gradeLabels[code] ?? code;
```

를 아래로 교체:

```dart
/// 부서 카탈로그: 미로드 시 const fallback, load 성공 시 DB 결과로 완전 교체.
/// 신규 협회 부서 추가가 DB INSERT 만으로 앱에 반영되게 하는 단일 진실 소스.
class DivisionCatalog {
  DivisionCatalog._();
  static final DivisionCatalog instance = DivisionCatalog._();

  // null = 미로드 → const fallback 사용.
  List<TennisDivision>? _ordered;
  Map<String, TennisDivision>? _byCode;

  bool get isLoaded => _ordered != null;

  /// 로드됐으면 DB 결과, 아니면 const fallback.
  List<TennisDivision> get all => _ordered ?? _kFallbackDivisions;

  TennisDivision? byCode(String code) =>
      (_byCode ?? _kFallbackByCode)[code];

  /// tennis_divisions 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 기존 상태를 유지한다.
  Future<void> load(SupabaseClient client) async {
    try {
      final rows = await client
          .from('tennis_divisions')
          .select('code, org_code, label_ko, gender')
          .eq('is_active', true)
          .order('code');
      ingestRows((rows as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // fallback 유지 — 앱 진입 차단 금지.
    }
  }

  /// DB row(또는 테스트 픽스처) → 카탈로그. org 우선순위로 그룹핑해 교체.
  @visibleForTesting
  void ingestRows(List<Map<String, dynamic>> rows) {
    final divisions = rows
        .map((r) => TennisDivision(
              code: r['code'] as String,
              org: r['org_code'] as String,
              label: r['label_ko'] as String,
              gender: (r['gender'] as String?) ?? 'all',
            ))
        .toList();
    final ordered = _sortByOrgPriority(divisions);
    _ordered = ordered;
    _byCode = {for (final d in ordered) d.code: d};
  }

  @visibleForTesting
  void reset() {
    _ordered = null;
    _byCode = null;
  }

  /// tennisOrgs 순서로 org 그룹핑(안정 정렬: 그룹 내 입력 순서 보존).
  /// DB 는 order('code') 로 오지만 협회 그룹핑이 흐트러지므로 재그룹핑한다.
  static List<TennisDivision> _sortByOrgPriority(List<TennisDivision> input) {
    final buckets = <String, List<TennisDivision>>{};
    final unknown = <TennisDivision>[];
    for (final d in input) {
      if (tennisOrgs.contains(d.org)) {
        (buckets[d.org] ??= <TennisDivision>[]).add(d);
      } else {
        unknown.add(d);
      }
    }
    final result = <TennisDivision>[];
    for (final org in tennisOrgs) {
      final bucket = buckets[org];
      if (bucket != null) result.addAll(bucket);
    }
    result.addAll(unknown);
    return result;
  }
}

const _kFallbackByCode = <String, TennisDivision>{};

/// 부서 목록: 카탈로그 위임(로드됐으면 DB, 아니면 const fallback).
List<TennisDivision> get tennisDivisions => DivisionCatalog.instance.all;

/// division 코드 → 표시명 (미등록 코드는 코드 그대로 반환)
String divisionLabel(String code) =>
    DivisionCatalog.instance.byCode(code)?.label ?? gradeLabels[code] ?? code;
```

주의: `_kFallbackByCode`는 fallback용 code→division 맵이어야 한다. 위 스텁(빈 맵)은 잘못됐다 — Step 6에서 실제 fallback 맵으로 채운다.

- [ ] **Step 6: `_kFallbackByCode`를 실제 fallback 맵으로 정의**

Step 5에서 넣은 `const _kFallbackByCode = <String, TennisDivision>{};` 한 줄을 아래로 교체(`const` 대신 `final` — 컴프리헨션은 const가 아님):

```dart
final _kFallbackByCode = <String, TennisDivision>{
  for (final d in _kFallbackDivisions) d.code: d,
};
```

이유: `byCode`는 미로드 시 `_byCode ?? _kFallbackByCode`로 fallback 조회해야 `divisionLabel('gj_m_gold')`이 로드 전에도 '골드부'를 반환한다.

- [ ] **Step 7: 나머지 위임 함수가 게터를 쓰는지 확인(대개 무변경)**

`divisionsForOrg`(line ~190), `tennisDivisionLabels`(~197), `tennisCodesForLabel`(~208), `tennisDivisionLabelsForOrg`(~223), `tennisCodesForLabelInOrg`(~234)는 이미 `tennisDivisions`를 참조한다. 이제 그게 게터이므로 자동 위임된다. **코드 변경 없음** — 참조가 유지되는지만 눈으로 확인.

`formatEligibleGrades`(~250)는 `divisionLabel`을 쓰므로 자동 위임. 변경 없음.

- [ ] **Step 8: 테스트 실행해 통과 확인(신규 + 기존 회귀)**

```bash
cd app && flutter test test/grade_labels_test.dart
```
Expected: PASS — 신규 `DivisionCatalog DB load` group 6개 + 기존 group 전부 통과. 기존 테스트는 카탈로그 미로드(fallback)라 순서·라벨 불변.

- [ ] **Step 9: analyze로 warning 0 확인**

```bash
cd app && flutter analyze lib/utils/grade_labels.dart test/grade_labels_test.dart
```
Expected: `No issues found!` (unused import 없어야 함 — `foundation`은 `@visibleForTesting`, `supabase_flutter`는 `SupabaseClient` 사용).

- [ ] **Step 10: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
git add app/lib/utils/grade_labels.dart app/test/grade_labels_test.dart
git commit -m "feat(app): JY-120 DivisionCatalog DB 로드 + top-level 함수 위임

const tennisDivisions 를 fallback 으로 두고 DivisionCatalog 싱글턴에 위임.
로드 전/실패 시 fallback, load 성공 시 DB 결과로 완전 교체.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: main.dart 인증 시점 카탈로그 로드 트리거

**Files:**
- Modify: `app/lib/main.dart:31-35`

**Interfaces:**
- Consumes: `DivisionCatalog`(Task 1), `Supabase.instance.client`.
- Produces: 없음(부수효과 — 인증 시 카탈로그 로드).

**배경:** 현재 `main.dart:31-35`는 `onAuthStateChange`에서 `signedIn`일 때만 `initNotifications`를 호출한다. `supabase_flutter`는 앱 시작 시 복원된 세션에 대해 `AuthChangeEvent.initialSession`을 발생시키므로, 이미 로그인된 사용자를 위해 `signedIn`과 `initialSession`(세션 존재 시) 둘 다에서 카탈로그를 로드해야 한다.

- [ ] **Step 1: grade_labels import 추가**

`app/lib/main.dart`의 import 블록(line 10-17 근처, `import 'config.dart';` 아래)에 추가:

```dart
import 'utils/grade_labels.dart';
```

- [ ] **Step 2: onAuthStateChange 리스너에 카탈로그 로드 추가**

`app/lib/main.dart:31-35` 기존:

```dart
  // 인증 후 FCM 등록 (실패해도 앱 진입 허용)
  Supabase.instance.client.auth.onAuthStateChange.listen((event) {
    if (event.event == AuthChangeEvent.signedIn) {
      initNotifications(ApiService(Supabase.instance.client));
    }
  });
```

를 아래로 교체:

```dart
  // 인증 후 FCM 등록 + 부서 카탈로그 DB 로드 (실패해도 앱 진입 허용)
  Supabase.instance.client.auth.onAuthStateChange.listen((event) {
    if (event.event == AuthChangeEvent.signedIn) {
      initNotifications(ApiService(Supabase.instance.client));
    }
    // signedIn(신규 로그인) + initialSession(복원 세션) 모두에서 로드.
    // RLS(tennis_divisions_read = authenticated) 이므로 세션 존재 시에만.
    if (event.session != null) {
      DivisionCatalog.instance.load(Supabase.instance.client);
    }
  });
```

- [ ] **Step 3: analyze로 warning 0 확인**

```bash
cd app && flutter analyze lib/main.dart
```
Expected: `No issues found!`

- [ ] **Step 4: 전체 테스트 스위트 회귀 확인**

```bash
cd app && flutter test
```
Expected: 전체 PASS(기존 + Task 1 신규). main.dart 위젯 테스트는 범위 밖(Supabase.initialize 필요) — 트리거 배선은 analyze + 리뷰로 검증(spec 명시).

- [ ] **Step 5: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
git add app/lib/main.dart
git commit -m "feat(app): JY-120 인증 시 부서 카탈로그 DB 로드 트리거

onAuthStateChange 에서 세션 존재(signedIn/initialSession) 시
DivisionCatalog.instance.load 호출.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review 노트

- **Spec 커버리지**: 상세 칩/온보딩/필터 3곳은 전부 `divisionLabel`·`tennisDivisions`·`tennisDivisionLabelsForOrg` 위임으로 해소(Task 1). 로드 트리거(Task 2). fallback 유지(Task 1 Step 4·6). org 우선순위 정렬(Task 1 `_sortByOrgPriority`). 성공기준 4개 모두 매핑됨.
- **위임 함수 무변경 근거**: 전 함수가 `tennisDivisions` 게터 또는 `divisionLabel`을 경유 → 카탈로그 자동 위임.
- **타입 일관성**: `ingestRows(List<Map<String, dynamic>>)` ↔ `load`가 `(rows as List).cast<Map<String, dynamic>>()`로 전달. `all`/`byCode`/`isLoaded`/`reset` 시그니처가 Task 1 테스트와 Task 2 호출부에서 일치.
- **범위 밖**(spec): const 완전 제거 안 함, regions/orgs DB화 안 함, KATO 라이브 활성화(seed 적용·enable·크롤)는 별도.
