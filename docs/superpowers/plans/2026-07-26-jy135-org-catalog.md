# JY-135 협회 카탈로그 DB 로드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 테니스 협회 목록·라벨의 정본을 Dart 하드코딩에서 DB `public.tennis_orgs` 로 옮겨, 협회 추가가 행 INSERT 하나로 앱에 반영되게 한다.

**Architecture:** 부서 카탈로그(`DivisionCatalog`, JY-120)와 같은 구조를 협회에 복제한다 — 싱글턴 + DB 로드 + const 폴백 + `whenReady` 스플래시 게이트 + `reset()` + load 세대 카운터 + `catalogRevision` 공유. 표시 문자열은 마이그레이션에서 **현재 앱 문자열 그대로** DB 에 백필해 화면 변화를 0 으로 만든다. 서버 검증은 제보 경로(`tournaments-submit`)만 DB 조회로 바꾼다.

**Tech Stack:** Flutter/Dart, Supabase Postgres(마이그레이션·RLS), Deno Edge Functions, pgTAP, flutter_test

**설계 문서:** `docs/superpowers/specs/2026-07-26-jy135-org-catalog-db-load-design.md`

> **파일명 정정(실행 후)**: 아래 태스크 1 이 지정한 `20260726020000_tennis_orgs_display_catalog.sql` ·
> `014_tennis_orgs_catalog.test.sql` 은 실행 중 main 에 머지된 #329 와 **번호가 충돌**해
> `20260726030000_...` · `015_...` 로 옮겼다. 마이그레이션 버전은 DB 기본키라 앞 14자리가
> 같으면 파일명이 달라도 중복 키 오류가 난다. 아래 본문의 옛 번호는 실행 당시 기록이다.

## Global Constraints

- 브랜치는 `feat/jy135-org-catalog`. **커밋 전 반드시 `git branch --show-current` 로 확인한다** — 이 저장소는 다른 세션과 공유돼 브랜치가 바뀌어 있을 수 있다.
- TypeScript `any` 금지, Dart `dynamic` 회피. 새 SQL 테이블·컬럼은 권한을 같은 마이그레이션에 명시(`docs/rules/DATABASE_RULES.md`).
- 마이그레이션 파일명은 `supabase/migrations/<14자리 timestamp>_<name>.sql`, 기존 최신(`20260726010000`)보다 뒤여야 한다.
- **표시 문자열은 현재 앱과 100% 동일해야 한다**: `label_ko` 는 `대한테니스협회 (KTA)` 형식, `short_label` 은 `광주협회`·`전남협회`·`시·군/클럽` 포함.
- 협회 표시 순서 정본은 `sort_order`. 쿼리는 항상 `order by sort_order, name_ko, code`.
- `tennis_orgs` 의 RLS 는 **변경하지 않는다**(로그인 후에만 읽기).
- 로컬 검증 명령: `cd app && flutter test`, `bash scripts/qa/run_db_tests.sh`, `bash scripts/harness/run_all.sh`.
- Edge 는 CI 자동배포가 없다. 머지 후 `tournaments-submit` 수동 배포가 필요하다.

---

### Task 1: 마이그레이션 — 표시 정본을 DB 로

**Files:**
- Create: `supabase/migrations/20260726020000_tennis_orgs_display_catalog.sql`
- Test: `supabase/tests/database/014_tennis_orgs_catalog.test.sql`

**Interfaces:**
- Consumes: 없음(첫 태스크)
- Produces: `public.tennis_orgs` 에 `label_ko text`, `sort_order integer not null default 1000` 컬럼. 10개 행의 `label_ko`·`short_label`·`sort_order` 백필 값. 이후 Task 2 의 `OrgCatalog.load()` 가 `code, label_ko, short_label, name_ko, org_type, is_active, sort_order` 를 읽는다.

- [ ] **Step 1: 실패하는 pgTAP 테스트 작성**

`supabase/tests/database/014_tennis_orgs_catalog.test.sql`:

```sql
-- JY-135: 협회 표시 정본(label_ko·short_label·sort_order)이 DB 에 있는지 검증한다.
-- 앱이 이 값을 그대로 화면에 쓰므로, 값이 어긋나면 사용자 화면 문구가 바뀐다.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(6);

SELECT has_column('public', 'tennis_orgs', 'label_ko', 'tennis_orgs 에 label_ko 가 있다');
SELECT has_column('public', 'tennis_orgs', 'sort_order', 'tennis_orgs 에 sort_order 가 있다');

-- sort_order 는 값을 안 정해도 INSERT 되어야 한다(백과장이 숫자를 산정할 필요 없음).
SELECT col_not_null('public', 'tennis_orgs', 'sort_order', 'sort_order 는 NOT NULL 이다');
SELECT col_default_is('public', 'tennis_orgs', 'sort_order', '1000',
  'sort_order 기본값은 1000 이라 미지정 행이 끝으로 모인다');

-- 표시 문자열이 현재 앱과 동일해야 한다. 다르면 화면 문구가 바뀐다.
SELECT is(
  (SELECT label_ko FROM public.tennis_orgs WHERE code = 'kta'),
  '대한테니스협회 (KTA)',
  'label_ko 는 앱이 쓰던 완성형 문자열이다'
);
SELECT is(
  (SELECT string_agg(short_label, ',' ORDER BY code)
     FROM public.tennis_orgs WHERE code IN ('gj', 'jn', 'local')),
  '광주협회,전남협회,시·군/클럽',
  '짧은 라벨이 앱 문자열로 백필됐다(GJTA/JNTA/null 아님)'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -X -tA -f supabase/tests/database/014_tennis_orgs_catalog.test.sql`
Expected: FAIL — `has_column` 이 `label_ko`/`sort_order` 없음으로 실패.

- [ ] **Step 3: 마이그레이션 작성**

`supabase/migrations/20260726020000_tennis_orgs_display_catalog.sql`:

```sql
-- JY-135: 협회 표시 정본을 Dart 하드코딩에서 DB 로 옮긴다.
--
-- 지금까지 협회 목록·라벨은 app/lib/utils/grade_labels.dart 의 const 3종
-- (tennisOrgs·tennisOrgLabels·tennisOrgShortLabels)이 정본이었다. 협회를 하나
-- 추가하려면 Dart·TS·데이터를 각각 고쳐야 했고, 실제로 tennis_orgs 테이블의
-- short_label 은 앱과 어긋나 있었다(gj=GJTA vs 앱 "광주협회", local=null).
--
-- 이 마이그레이션 뒤에는 tennis_orgs 가 정본이다. 협회 추가 = 행 INSERT 하나.

alter table public.tennis_orgs
  add column if not exists label_ko text,
  -- 표시 순서 정본. not null default 1000 이라 값을 안 정해도 INSERT 되고,
  -- 지정하지 않은 행은 끝으로 모인다(정렬은 sort_order, name_ko, code).
  add column if not exists sort_order integer not null default 1000;

comment on column public.tennis_orgs.label_ko is
  '온보딩·프로필에 그대로 표시되는 완성형 라벨. 비면 name_ko 로 폴백한다(JY-135).';
comment on column public.tennis_orgs.short_label is
  '칩·요약에 쓰는 짧은 라벨. 화면에 보일 문자열 그대로 넣는다(JY-135).';
comment on column public.tennis_orgs.sort_order is
  '표시 순서. 작을수록 앞. 미지정(1000)이면 name_ko·code 순으로 뒤에 붙는다(JY-135).';

-- 현재 앱 문자열 그대로 백필한다. 값이 다르면 사용자 화면 문구가 바뀐다.
-- sort_order 는 기존 Dart 배열 순서를 10 간격으로 부여해 사이에 끼울 수 있게 둔다.
update public.tennis_orgs as t
   set label_ko = v.label_ko,
       short_label = v.short_label,
       sort_order = v.sort_order
  from (values
    ('kta',   '대한테니스협회 (KTA)',                  'KTA',      10),
    ('kato',  '한국테니스발전협의회 (KATO)',           'KATO',     20),
    ('kata',  '한국동호인테니스협회 (KATA)',           'KATA',     30),
    ('ktfs',  '국민생활체육 전국테니스연합회 (KTFS)',  'KTFS',     40),
    ('kstf',  '한국시니어테니스연맹 (KSTF, 60+)',      'KSTF',     50),
    ('kssta', '한국슈퍼시니어테니스협회 (KSSTA)',      'KSSTA',    60),
    ('kasta', '단식 테니스 (KASTA / 단테매)',          'KASTA',    70),
    ('gj',    '광주광역시테니스협회 (GJTA)',           '광주협회', 80),
    ('jn',    '전라남도테니스협회 (JNTA)',             '전남협회', 90),
    ('local', '시·군 또는 클럽 자체',                  '시·군/클럽', 100)
  ) as v(code, label_ko, short_label, sort_order)
 where t.code = v.code;

-- 컬럼 추가는 기존 테이블 권한을 그대로 상속한다(신규 테이블이 아니므로 grant 불필요).
-- RLS 는 건드리지 않는다 — tennis_orgs_read(authenticated) 유지.
```

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
supabase db reset && bash scripts/qa/run_db_tests.sh
```
Expected: `014_tennis_orgs_catalog.test.sql ok=6`, 전체 스위트 통과.

- [ ] **Step 5: 커밋**

```bash
git branch --show-current   # feat/jy135-org-catalog 인지 확인
git add supabase/migrations/20260726020000_tennis_orgs_display_catalog.sql supabase/tests/database/014_tennis_orgs_catalog.test.sql
git commit -m "feat(db): 협회 표시 정본을 tennis_orgs 로 — label_ko·sort_order (#JY-135)"
```

---

### Task 2: `OrgCatalog` — DB 로드 + 폴백

**Files:**
- Modify: `app/lib/utils/grade_labels.dart` (`tennisOrgs`/`tennisOrgLabels`/`tennisOrgShortLabels` 정의부 525-566 부근)
- Test: `app/test/grade_labels_test.dart`

**Interfaces:**
- Consumes: Task 1 의 `tennis_orgs.label_ko`·`short_label`·`sort_order`
- Produces:
  - `class TennisOrgEntry { final String code; final String label; final String shortLabel; final bool isActive; }`
  - `OrgCatalog.instance` — `List<String> get activeCodes`, `String labelFor(String code)`, `String shortLabelFor(String code)`, `Future<void> load(SupabaseClient)`, `Future<void> get whenReady`, `void reset()`, `void ingestRows(List<Map<String, dynamic>>)`
  - 하위호환 게터/함수: `List<String> get tennisOrgs`, `String tennisOrgLabel(String)`, `String tennisOrgShortLabel(String)` — 기존 소비처가 그대로 컴파일되도록 유지(내부는 카탈로그 경유)

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/grade_labels_test.dart` 의 카탈로그 그룹에 추가:

```dart
  group('OrgCatalog', () {
    tearDown(() => OrgCatalog.instance.reset());

    test('미로드 시 폴백 목록·라벨을 쓴다', () {
      expect(OrgCatalog.instance.isLoaded, isFalse);
      expect(tennisOrgs.first, 'kta');
      expect(tennisOrgLabel('kta'), '대한테니스협회 (KTA)');
      expect(tennisOrgShortLabel('gj'), '광주협회');
    });

    test('ingestRows 는 sort_order 순으로 정렬하고 비활성은 목록에서 뺀다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'jn', 'label_ko': '전남', 'short_label': '전남협회',
         'name_ko': '전라남도테니스협회', 'is_active': true, 'sort_order': 90},
        {'code': 'kta', 'label_ko': 'KTA 라벨', 'short_label': 'KTA',
         'name_ko': '대한테니스협회', 'is_active': true, 'sort_order': 10},
        {'code': 'ktfs', 'label_ko': '폐지협회', 'short_label': 'KTFS',
         'name_ko': '국민생활체육', 'is_active': false, 'sort_order': 40},
      ]);
      expect(tennisOrgs, ['kta', 'jn']); // 비활성 ktfs 제외, sort_order 순
      expect(tennisOrgLabel('kta'), 'KTA 라벨');
    });

    test('비활성 협회도 라벨 조회는 된다(보유자 화면에 코드가 노출되면 안 됨)', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'ktfs', 'label_ko': '국민생활체육 전국테니스연합회 (KTFS)',
         'short_label': 'KTFS', 'name_ko': '국민생활체육', 'is_active': false,
         'sort_order': 40},
      ]);
      expect(tennisOrgs, isNot(contains('ktfs')));
      expect(tennisOrgLabel('ktfs'), '국민생활체육 전국테니스연합회 (KTFS)');
    });

    test('label_ko 가 비면 name_ko 로 폴백한다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'new1', 'label_ko': null, 'short_label': null,
         'name_ko': '새협회', 'is_active': true, 'sort_order': 1000},
      ]);
      expect(tennisOrgLabel('new1'), '새협회');
      expect(tennisOrgShortLabel('new1'), '새협회');
    });

    test('reset 후 폴백으로 복귀한다', () {
      OrgCatalog.instance.ingestRows([
        {'code': 'kta', 'label_ko': 'X', 'short_label': 'X',
         'name_ko': 'X', 'is_active': true, 'sort_order': 10},
      ]);
      expect(OrgCatalog.instance.isLoaded, isTrue);
      OrgCatalog.instance.reset();
      expect(OrgCatalog.instance.isLoaded, isFalse);
      expect(tennisOrgLabel('kta'), '대한테니스협회 (KTA)');
    });
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd app && flutter test test/grade_labels_test.dart --plain-name OrgCatalog`
Expected: FAIL — `OrgCatalog` 정의 없음(컴파일 에러).

- [ ] **Step 3: `OrgCatalog` 구현**

`app/lib/utils/grade_labels.dart` 에서 기존 `const tennisOrgs` / `tennisOrgLabels` / `tennisOrgShortLabels` 를 폴백으로 이름만 바꾸고(`_kFallbackOrgs` 등) 아래를 추가한다. 기존 공개 심볼은 게터로 유지해 소비처가 안 깨지게 한다.

```dart
/// 협회 카탈로그 항목. 정본은 DB public.tennis_orgs 다(JY-135).
class TennisOrgEntry {
  const TennisOrgEntry({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.isActive,
  });

  final String code;
  final String label;
  final String shortLabel;
  final bool isActive;
}

/// 협회 목록·라벨 카탈로그. DivisionCatalog 와 같은 구조다(JY-120 선례).
///
/// 협회 추가는 tennis_orgs 에 행을 넣는 것만으로 끝난다 — 앱 재배포가 필요 없다.
class OrgCatalog {
  OrgCatalog._();
  static final OrgCatalog instance = OrgCatalog._();

  // null = 미로드 → const 폴백 사용.
  List<TennisOrgEntry>? _ordered;
  Map<String, TennisOrgEntry>? _byCode;

  Completer<void> _ready = Completer<void>();
  int _generation = 0;
  Future<void> get whenReady => _ready.future;
  void _markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  bool get isLoaded => _ordered != null;

  List<TennisOrgEntry> get all => _ordered ?? _kFallbackOrgEntries;

  /// 선택지에 노출할 활성 협회 코드(표시 순서).
  List<String> get activeCodes =>
      all.where((o) => o.isActive).map((o) => o.code).toList(growable: false);

  /// 라벨 조회는 활성 여부와 무관하다 — 비활성 협회를 이미 가진 사용자의
  /// 화면에 코드가 그대로 노출되면 안 된다.
  String labelFor(String code) =>
      (_byCode ?? _kFallbackOrgByCode)[code]?.label ?? code;

  String shortLabelFor(String code) =>
      (_byCode ?? _kFallbackOrgByCode)[code]?.shortLabel ?? code;

  /// tennis_orgs 를 읽어 카탈로그를 교체한다(멱등).
  /// 실패(네트워크/RLS/타임아웃) 시 예외를 삼키고 폴백을 유지한다.
  Future<void> load(SupabaseClient client) async {
    final gen = ++_generation;
    try {
      final rows = await client
          .from('tennis_orgs')
          .select('code, label_ko, short_label, name_ko, is_active, sort_order')
          .order('sort_order')
          .order('name_ko')
          .order('code');
      if (gen == _generation) {
        ingestRows((rows as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // 폴백 유지 — 앱 진입을 막지 않는다.
    } finally {
      if (gen == _generation) _markReady();
    }
  }

  /// DB row(또는 테스트 픽스처) → 카탈로그.
  /// label_ko 가 비면 name_ko 로, short_label 이 비면 label 로 폴백한다.
  @visibleForTesting
  void ingestRows(List<Map<String, dynamic>> rows) {
    final entries = rows.map((r) {
      final code = r['code'] as String;
      final label = (r['label_ko'] as String?) ?? (r['name_ko'] as String?) ?? code;
      return TennisOrgEntry(
        code: code,
        label: label,
        shortLabel: (r['short_label'] as String?) ?? label,
        isActive: (r['is_active'] as bool?) ?? true,
      );
    }).toList();
    // 정렬은 쿼리(order by sort_order, name_ko, code)가 한다. 여기서는 입력 순서를 보존한다.
    _ordered = entries;
    _byCode = {for (final e in entries) e.code: e};
    _markReady();
    catalogRevision.value++;
  }

  /// 세션 전환(로그아웃·계정 변경) 시 호출한다.
  void reset() {
    _ordered = null;
    _byCode = null;
    _ready = Completer<void>();
    _generation++;
    catalogRevision.value++;
  }
}

/// 협회 코드(표시 순서, 활성만). 로드됐으면 DB, 아니면 const 폴백.
List<String> get tennisOrgs => OrgCatalog.instance.activeCodes;

/// 협회 코드 → 완성형 라벨.
String tennisOrgLabel(String org) => OrgCatalog.instance.labelFor(org);

/// 협회 코드 → 짧은 라벨(칩·요약용).
String tennisOrgShortLabel(String org) => OrgCatalog.instance.shortLabelFor(org);
```

폴백 상수는 기존 값을 그대로 옮긴다:

```dart
// 협회 정본은 DB public.tennis_orgs 다(JY-135). 아래 const 는 미로드 시 쓰는
// 오프라인 폴백이며, 값은 마이그레이션 백필과 같아야 한다.
const _kFallbackOrgEntries = <TennisOrgEntry>[
  TennisOrgEntry(code: 'kta', label: '대한테니스협회 (KTA)', shortLabel: 'KTA', isActive: true),
  TennisOrgEntry(code: 'kato', label: '한국테니스발전협의회 (KATO)', shortLabel: 'KATO', isActive: true),
  TennisOrgEntry(code: 'kata', label: '한국동호인테니스협회 (KATA)', shortLabel: 'KATA', isActive: true),
  TennisOrgEntry(code: 'ktfs', label: '국민생활체육 전국테니스연합회 (KTFS)', shortLabel: 'KTFS', isActive: true),
  TennisOrgEntry(code: 'kstf', label: '한국시니어테니스연맹 (KSTF, 60+)', shortLabel: 'KSTF', isActive: true),
  TennisOrgEntry(code: 'kssta', label: '한국슈퍼시니어테니스협회 (KSSTA)', shortLabel: 'KSSTA', isActive: true),
  TennisOrgEntry(code: 'kasta', label: '단식 테니스 (KASTA / 단테매)', shortLabel: 'KASTA', isActive: true),
  TennisOrgEntry(code: 'gj', label: '광주광역시테니스협회 (GJTA)', shortLabel: '광주협회', isActive: true),
  TennisOrgEntry(code: 'jn', label: '전라남도테니스협회 (JNTA)', shortLabel: '전남협회', isActive: true),
  TennisOrgEntry(code: 'local', label: '시·군 또는 클럽 자체', shortLabel: '시·군/클럽', isActive: true),
];

final _kFallbackOrgByCode = {for (final e in _kFallbackOrgEntries) e.code: e};
```

기존 `bool isValidTennisOrg(String value)`(호출부 0건)는 삭제한다.

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd app && flutter test test/grade_labels_test.dart`
Expected: PASS (신규 OrgCatalog 5개 포함).

- [ ] **Step 5: 커밋**

```bash
git branch --show-current
git add app/lib/utils/grade_labels.dart app/test/grade_labels_test.dart
git commit -m "feat(app): OrgCatalog — 협회 목록·라벨 DB 로드 + 폴백 (#JY-135)"
```

---

### Task 3: 부서 정렬을 카탈로그 순서로 + 생명주기 배선

**Files:**
- Modify: `app/lib/utils/grade_labels.dart:405-420` (`_sortByOrgPriority`)
- Modify: `app/lib/main.dart:58`(load), `:64`(reset), `:242`(whenReady)
- Test: `app/test/grade_labels_test.dart`, `app/test/catalog_rebuild_test.dart`

**Interfaces:**
- Consumes: Task 2 의 `OrgCatalog.instance`, `tennisOrgs`
- Produces: 앱 시작·로그아웃 시 `OrgCatalog` 가 `DivisionCatalog` 와 같은 시점에 로드·리셋된다. 부서 그룹 순서가 협회 카탈로그 순서를 따른다.

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/grade_labels_test.dart` 에 추가:

```dart
    test('부서 그룹 순서는 OrgCatalog 순서를 따른다(DB sort_order 반영)', () {
      // 협회 순서를 뒤집어 로드하면 부서 그룹 순서도 따라 뒤집혀야 한다.
      OrgCatalog.instance.ingestRows([
        {'code': 'gj', 'label_ko': '광주', 'short_label': '광주협회',
         'name_ko': '광주', 'is_active': true, 'sort_order': 10},
        {'code': 'kta', 'label_ko': 'KTA', 'short_label': 'KTA',
         'name_ko': 'KTA', 'is_active': true, 'sort_order': 20},
      ]);
      DivisionCatalog.instance.ingestRows([
        {'code': 'kta_a', 'org_code': 'kta', 'label_ko': 'KTA-A', 'gender': 'all'},
        {'code': 'gj_a', 'org_code': 'gj', 'label_ko': 'GJ-A', 'gender': 'all'},
      ]);
      final orgs = DivisionCatalog.instance.all.map((d) => d.org).toList();
      expect(orgs, ['gj', 'kta']); // OrgCatalog 순서(gj 가 앞)
    });
```

`app/test/catalog_rebuild_test.dart` 의 `tearDown` 에 추가:

```dart
  tearDown(() {
    GradeCatalog.instance.reset();
    DivisionCatalog.instance.reset();
    OrgCatalog.instance.reset();
  });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd app && flutter test test/grade_labels_test.dart --plain-name 'OrgCatalog 순서'`
Expected: FAIL — `_sortByOrgPriority` 가 아직 const 폴백 순서를 쓰므로 `['kta','gj']` 가 나온다.

- [ ] **Step 3: 정렬·배선 수정**

`grade_labels.dart` 의 `_sortByOrgPriority` 에서 순서 출처를 카탈로그로 바꾼다. 기존 코드가 `tennisOrgs` 를 참조하고 있고 Task 2 에서 그 게터가 카탈로그를 보게 됐으므로, **활성만 담긴 `tennisOrgs` 로는 비활성 협회의 부서가 누락된다.** 전체 코드 목록을 쓰도록 바꾼다:

```dart
  /// OrgCatalog 순서로 org 그룹핑(안정 정렬: 그룹 내 입력 순서 보존).
  /// 비활성 협회의 부서도 순서를 가져야 하므로 activeCodes 가 아니라 all 을 쓴다.
  static List<TennisDivision> _sortByOrgPriority(List<TennisDivision> input) {
    final orgOrder = OrgCatalog.instance.all.map((o) => o.code).toList();
    final buckets = <String, List<TennisDivision>>{};
    final unknown = <TennisDivision>[];
    for (final d in input) {
      if (orgOrder.contains(d.org)) {
        buckets.putIfAbsent(d.org, () => []).add(d);
      } else {
        unknown.add(d);
      }
    }
    final out = <TennisDivision>[];
    for (final org in orgOrder) {
      final bucket = buckets[org];
      if (bucket != null) out.addAll(bucket);
    }
    out.addAll(unknown);
    return out;
  }
```

`app/lib/main.dart` 세 지점:

```dart
    // :58 부근 — 세션이 있을 때 로드
    if (event.session != null) {
      DivisionCatalog.instance.load(Supabase.instance.client);
      GradeCatalog.instance.load(Supabase.instance.client);
      OrgCatalog.instance.load(Supabase.instance.client);
    } else if (event.event == AuthChangeEvent.signedOut) {
      GradeCatalog.instance.reset();
      DivisionCatalog.instance.reset();
      OrgCatalog.instance.reset();
    }
```

```dart
    // :242 부근 — 스플래시 게이트에 추가(기존 DivisionCatalog 과 같은 timeout)
        OrgCatalog.instance.whenReady
            .timeout(const Duration(milliseconds: 3000), onTimeout: () {}),
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd app && flutter test`
Expected: PASS 전체.

- [ ] **Step 5: 커밋**

```bash
git branch --show-current
git add app/lib/utils/grade_labels.dart app/lib/main.dart app/test/grade_labels_test.dart app/test/catalog_rebuild_test.dart
git commit -m "feat(app): 부서 정렬을 협회 카탈로그 순서로 + 로드·리셋 배선 (#JY-135)"
```

---

### Task 4: 제보 화면의 두 번째 하드코딩 목록 통합

**Files:**
- Modify: `app/lib/screens/tournaments/tournament_submit_screen.dart:143-151` (`_tennisOrgOptions`), `:315,317,323`(드롭다운), `:33`/`:250`(기본값)
- Test: `app/test/tournament_submit_org_options_test.dart` (신규)

**Interfaces:**
- Consumes: Task 2 의 `tennisOrgs`, `tennisOrgLabel`
- Produces: 제보 화면 협회 선택지가 카탈로그를 따른다(별도 목록 없음).

- [ ] **Step 1: 실패하는 테스트 작성**

`app/test/tournament_submit_org_options_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 제보 화면이 별도 협회 목록을 갖고 있으면, 협회를 DB 에 추가해도 이 화면에서만
// 조용히 누락된다(JY-135). 소스를 직접 읽어 두 번째 목록의 부활을 막는다.
//
// 소스 검사로 가는 이유: 목록이 private const 라 위젯을 띄우지 않고는 값을 볼 수
// 없는데, 위젯 테스트는 이 화면의 폼·프로바이더를 통째로 세워야 해 비용이 크다.
// 같은 저장소의 catalog_rebuild_test.dart:74-91 이 router.dart 를 파싱해 규칙을
// 강제하는 선례를 따른다.
void main() {
  test('제보 화면에 협회 하드코딩 목록이 없다', () {
    final src = File('lib/screens/tournaments/tournament_submit_screen.dart')
        .readAsStringSync();
    expect(src.contains('_tennisOrgOptions'), isFalse,
        reason: '협회 선택지는 OrgCatalog(tennisOrgs)를 써야 한다');
    // 코드 리터럴을 나열한 별도 목록이 되살아나는 것도 막는다.
    expect(src.contains("('kta'"), isFalse,
        reason: '협회 코드를 화면에 나열하지 말 것');
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd app && flutter test test/tournament_submit_org_options_test.dart`
Expected: FAIL — `_tennisOrgOptions` 가 아직 파일에 있어 두 expect 가 모두 실패한다.

- [ ] **Step 3: 화면을 카탈로그로 전환**

`tournament_submit_screen.dart` 에서 `_tennisOrgOptions` 상수를 삭제하고, 드롭다운이 카탈로그를 쓰게 한다:

```dart
  // 협회 선택지는 OrgCatalog(정본 = DB tennis_orgs)를 그대로 쓴다.
  // 별도 목록을 두면 협회 추가가 이 화면에서만 조용히 누락된다(JY-135).
  List<DropdownMenuItem<String>> _orgItems() => [
        for (final code in tennisOrgs)
          DropdownMenuItem(value: code, child: Text(tennisOrgLabel(code))),
      ];
```

기본값 `'gj'` 하드코딩(`:33`, `:250`)은 카탈로그 첫 항목으로 바꾼다:

```dart
  // 카탈로그가 비어 있을 일은 없지만(폴백 보장), 방어적으로 'gj' 를 남긴다.
  String _defaultOrg() => tennisOrgs.isNotEmpty ? tennisOrgs.first : 'gj';
```

드롭다운 사용처(`:315,317,323`)를 `_orgItems()` 로 교체한다.

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
cd app && flutter test
grep -n "_tennisOrgOptions" lib/screens/tournaments/tournament_submit_screen.dart || echo "제거 확인"
```
Expected: 테스트 전체 PASS, grep 결과 "제거 확인".

- [ ] **Step 5: 커밋**

```bash
git branch --show-current
git add app/lib/screens/tournaments/tournament_submit_screen.dart app/test/tournament_submit_org_options_test.dart
git commit -m "fix(app): 제보 화면 협회 목록을 카탈로그로 통합 — 조용한 누락 차단 (#JY-135)"
```

---

### Task 5: 제보 Edge 검증을 DB 조회로

**Files:**
- Modify: `supabase/functions/tournaments-submit/index.ts:271` 부근(`isValidTennisOrg` 사용부)
- Test: `supabase/functions/tests/tournaments_submit_org_test.ts` (신규)

**Interfaces:**
- Consumes: Task 1 의 `tennis_orgs.is_active`
- Produces: `async function assertKnownOrgs(client, orgs: string[]): Promise<string | null>` — 알 수 없거나 비활성인 협회가 있으면 에러 메시지를, 없으면 `null` 을 반환한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`supabase/functions/tests/tournaments_submit_org_test.ts`:

```ts
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { assertKnownOrgs } from '../tournaments-submit/index.ts';

// 협회 정본은 DB tennis_orgs 다(JY-135). 정적 목록으로 검증하면 DB 에 협회를
// 추가해도 제보가 거절된다 — "행 INSERT 하나로 반영" 이 깨진다.
function fakeClient(rows: Array<{ code: string }>) {
  return {
    from: () => ({
      select: () => ({
        in: () => ({ eq: () => Promise.resolve({ data: rows, error: null }) }),
      }),
    }),
  } as unknown as Parameters<typeof assertKnownOrgs>[0];
}

Deno.test('DB 에 있는 활성 협회는 통과한다', async () => {
  const err = await assertKnownOrgs(fakeClient([{ code: 'seoul' }]), ['seoul']);
  assertEquals(err, null);
});

Deno.test('DB 에 없는 협회는 거절한다', async () => {
  const err = await assertKnownOrgs(fakeClient([]), ['nope']);
  assertEquals(err, 'invalid org: nope');
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd supabase/functions && deno test --config deno.json --allow-env --allow-read tests/tournaments_submit_org_test.ts`
Expected: FAIL — `assertKnownOrgs` export 없음.

- [ ] **Step 3: 구현**

`tournaments-submit/index.ts` 에서 정적 검증을 DB 조회로 교체한다:

```ts
/**
 * 협회 코드가 DB(tennis_orgs)에 있고 활성인지 확인한다.
 * 정적 목록(TENNIS_ORGS)으로 검증하면 협회를 DB 에 추가해도 제보가 거절된다(JY-135).
 * 제보는 쓰기 경로라 빈도가 낮아 조회 1회 비용이 무의미하다.
 */
export async function assertKnownOrgs(
  client: SupabaseClient,
  orgs: string[],
): Promise<string | null> {
  if (orgs.length === 0) return null;
  const { data, error } = await client
    .from('tennis_orgs')
    .select('code')
    .in('code', orgs)
    .eq('is_active', true);
  if (error) return 'org 검증에 실패했습니다';
  const known = new Set((data ?? []).map((r: { code: string }) => r.code));
  const unknown = orgs.find((o) => !known.has(o));
  return unknown ? `invalid org: ${unknown}` : null;
}
```

기존 `:271` 의 루프를 교체한다:

```ts
      const orgError = await assertKnownOrgs(supabase, hostOrgs.value ?? []);
      if (orgError) {
        return errorResponse(orgError);
      }
```

`isValidTennisOrg` import 가 이 파일에서 더 이상 안 쓰이면 제거한다(`tournaments-search` 는 그대로 둔다 — 후속 이슈).

- [ ] **Step 4: 테스트 통과 확인**

Run:
```bash
cd supabase/functions
deno test --config deno.json --allow-env --allow-read tests
deno fmt --check */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
deno lint --config deno.json */*.ts _shared/*.ts _shared/crawler/parsers/*.ts tests/*.ts
```
Expected: 전부 PASS (fmt·lint 도 CI 필수 검사다).

- [ ] **Step 5: 커밋**

```bash
git branch --show-current
git add supabase/functions/tournaments-submit/index.ts supabase/functions/tests/tournaments_submit_org_test.ts
git commit -m "feat(edge): 제보 협회 검증을 DB 조회로 — 새 협회가 거절되지 않게 (#JY-135)"
```

---

### Task 6: 죽은 게이트 정리 + 전체 검증

**Files:**
- Modify: `scripts/harness/check_enums.py:179-182` (`tennis orgs` 3층 비교)

**Interfaces:**
- Consumes: Task 2 에서 Dart `tennisOrgs` const 가 사라진 상태
- Produces: harness 게이트가 죽은 SQL enum 을 참조하지 않는다.

- [ ] **Step 1: 현재 게이트가 깨지는지 확인**

Run: `python3 scripts/harness/check_enums.py`
Expected: FAIL — Dart `const tennisOrgs = <String>[...]` 가 사라져 정규식 파싱이 실패한다.

- [ ] **Step 2: 게이트에서 협회 3층 비교 제거**

`check_enums.py` 의 `assert_same("tennis orgs", ...)` 블록을 삭제하고 이유를 남긴다:

```python
    # 협회(tennis_orgs)의 정본은 DB 다(JY-135). Dart 는 폴백만 갖고 SQL enum 은
    # 20260711002939 에서 이미 삭제됐다 — 이 검사는 죽은 타입 텍스트를 파싱하고
    # 있었다. 등급이 JY-321 에서 실제 DB 조회로 옮겨간 것과 같은 방향이다.
    # 후속: 폴백↔DB 대조를 check_grades_parity.py 방식으로 추가.
```

`sql_orgs` 변수와 그 파일 로드가 다른 곳에서 안 쓰이면 함께 제거한다.

- [ ] **Step 3: 게이트 통과 확인**

Run: `python3 scripts/harness/check_enums.py`
Expected: PASS.

- [ ] **Step 4: 전체 검증**

Run:
```bash
supabase db reset && bash scripts/qa/run_db_tests.sh
bash scripts/harness/run_all.sh
cd app && flutter test
```
Expected: pgTAP 전체 통과(`014` 포함), harness 통과, flutter test 전체 통과.

- [ ] **Step 5: 커밋**

```bash
git branch --show-current
git add scripts/harness/check_enums.py
git commit -m "chore(harness): 협회 3층 비교 제거 — 삭제된 SQL enum 참조 (#JY-135)"
```

---

## 완료 조건

- `supabase db reset` 후 pgTAP 전체 통과(신규 `014_tennis_orgs_catalog.test.sql` 포함)
- `cd app && flutter test` 전체 통과
- `bash scripts/harness/run_all.sh` 통과
- `grep -rn "_tennisOrgOptions\|const tennisOrgs" app/lib/` 결과 없음
- 앱 화면 문구가 변경 전과 동일(라벨 백필 확인)

## 머지 후 필수 작업

1. `supabase db push --linked` 로 마이그레이션 적용
2. **`supabase functions deploy tournaments-submit`** — Edge 는 CI 자동배포가 없다
3. 후속 이슈 생성: `tournaments-search` 검증의 DB 전환(**15개 실데이터 추가 전 필수 선행**), `chat` 협회 라벨 DB 전환
