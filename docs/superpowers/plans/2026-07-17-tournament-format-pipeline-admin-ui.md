# 대회 요강 정형화 파이프라인 — Plan 5: 검수 UI + 앱 표시 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 published 대회의 정형화 결과(`format_staged`)를 어드민이 원문과 대조해 승인/반려하는 검수 화면과, 앱의 `format_status` 타입화를 추가한다.

**Architecture:** DB에 `format_apply_staged`/`format_reject_staged`(admin 전용) RPC를 만들고, 어드민 `/admin/format-review` 화면이 `needs_review & format_staged` 목록을 보여준다. 승인 시 staged jsonb를 콘텐츠 컬럼으로 반영한다. 앱 모델에 `FormatStatus` enum을 추가(사용자 표시는 무변, 어드민만 사용).

**Tech Stack:** Flutter(Riverpod, go_router), Supabase Postgres(RPC), Dart.

## Global Constraints

- Plan 1 선행: `format_status/format_staged` 컬럼, `guard_tournament_format_columns` 트리거(admin/service만 format_* 변경 허용) 존재.
- Dart `dynamic` 금지. `flutter analyze` warning=error(unused 제거 필수).
- 마이그레이션: `apply_migration`(db push 금지), 끝에 `NOTIFY pgrst, 'reload schema'`.
- 사용자 화면(tournament_detail)은 변경 없음 — 이미 regulation 카드 렌더, format_status 비노출.
- 커밋 끝: `Refs: JY-137` + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: 앱 모델 — FormatStatus enum

**Files:**
- Modify: `app/lib/models/tournament.dart` (enum 추가 + `Tournament.fromJson`)
- Test: `app/test/tournament_format_status_test.dart` (신규)

**Interfaces:**
- Produces: `enum FormatStatus { pending, processing, formatted, needsReview, failed, skipped }` + `FormatStatus.fromString(String?)`; `Tournament.formatStatus` 필드.

- [ ] **Step 1: 실패 테스트**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:allround/models/tournament.dart';

void main() {
  test('FormatStatus.fromString 매핑', () {
    expect(FormatStatus.fromString('needs_review'), FormatStatus.needsReview);
    expect(FormatStatus.fromString('formatted'), FormatStatus.formatted);
    expect(FormatStatus.fromString('skipped'), FormatStatus.skipped);
    expect(FormatStatus.fromString(null), FormatStatus.pending);
    expect(FormatStatus.fromString('bogus'), FormatStatus.pending);
  });
}
```

`allround` 패키지명은 `app/pubspec.yaml`의 `name:`을 확인해 정확히 사용(다르면 교체).

- [ ] **Step 2: 실패 확인**

Run: `cd app && flutter test test/tournament_format_status_test.dart`
Expected: FAIL — `FormatStatus` 미정의.

- [ ] **Step 3: enum + 파싱 추가**

`tournament.dart`의 `RegulationField` 위(파일 상단)에 enum 추가:

```dart
enum FormatStatus {
  pending,
  processing,
  formatted,
  needsReview,
  failed,
  skipped;

  static FormatStatus fromString(String? s) {
    switch (s) {
      case 'processing':
        return FormatStatus.processing;
      case 'formatted':
        return FormatStatus.formatted;
      case 'needs_review':
        return FormatStatus.needsReview;
      case 'failed':
        return FormatStatus.failed;
      case 'skipped':
        return FormatStatus.skipped;
      case 'pending':
      default:
        return FormatStatus.pending;
    }
  }
}
```

`Tournament` 클래스에 필드 추가(`final String status;` 인접):

```dart
  final FormatStatus formatStatus;
```

생성자 파라미터에 `required this.formatStatus,`(또는 기본값 `this.formatStatus = FormatStatus.pending,`) 추가. `Tournament.fromJson`에:

```dart
      formatStatus: FormatStatus.fromString(j['format_status'] as String?),
```

- [ ] **Step 4: 통과 확인 + analyze**

Run: `cd app && flutter test test/tournament_format_status_test.dart` → PASS.
Run: `cd app && flutter analyze` → No issues(unused 없음).

- [ ] **Step 5: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
git add app/lib/models/tournament.dart app/test/tournament_format_status_test.dart
git commit -m "feat(app): FormatStatus enum + Tournament.formatStatus 파싱

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: staged 승인/반려 RPC (마이그레이션)

**Files:**
- Create: `supabase/migrations/20260717HHMMSS_format_staged_rpc.sql`

**Interfaces:**
- Produces: `format_apply_staged(p_tid uuid) returns boolean`(admin 전용, staged→콘텐츠 반영+formatted), `format_reject_staged(p_tid uuid, p_reason text) returns boolean`(admin 전용, staged 폐기+failed+사유 flag).

- [ ] **Step 1: RPC 작성 + apply_migration**

```sql
-- 요강 정형화 검수 스테이징 승인/반려 RPC (admin 전용).
create or replace function public.format_apply_staged(p_tid uuid)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare s jsonb; v int;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select format_staged into s from public.tournaments where id = p_tid;
  if s is null then return false; end if;
  update public.tournaments t set
    regulation_fields = s -> 'regulation_fields',
    regulation_notes = (
      select array_agg(x)::text[]
      from jsonb_array_elements_text(coalesce(s -> 'regulation_notes', '[]'::jsonb)) x
    ),
    regulation_body = nullif(s ->> 'regulation_body', ''),
    prize = nullif(s ->> 'prize', ''),
    format = nullif(s ->> 'format', ''),
    description = nullif(s ->> 'description', ''),
    format_status = 'formatted', formatted_at = now(), format_staged = null
  where t.id = p_tid;
  get diagnostics v = row_count;
  return v > 0;
end;
$$;

create or replace function public.format_reject_staged(p_tid uuid, p_reason text)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v int;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  update public.tournaments t set
    format_status = 'failed', format_staged = null,
    format_flags = coalesce(t.format_flags, '[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('code','admin_reject','field','_admin',
        'masked', left(coalesce(p_reason,''), 200)))
  where t.id = p_tid and t.format_staged is not null;
  get diagnostics v = row_count;
  return v > 0;
end;
$$;

revoke execute on function public.format_apply_staged(uuid) from public, anon;
revoke execute on function public.format_reject_staged(uuid, text) from public, anon;
grant execute on function public.format_apply_staged(uuid) to authenticated;   -- 내부 is_admin() 게이트
grant execute on function public.format_reject_staged(uuid, text) to authenticated;

notify pgrst, 'reload schema';
```
Run: `apply_migration` name=`format_staged_rpc`, query=위 전문.

- [ ] **Step 2: 검증**

Run(`execute_sql`, staged 있는 행이 아직 없으면 임시 세팅 후):
```sql
-- 임시: 한 행에 staged 세팅 → apply → 콘텐츠 반영 확인 → 원복
do $$
declare tid uuid;
begin
  select id into tid from public.tournaments where format_status='pending' limit 1;
  update public.tournaments set format_status='needs_review',
    format_staged = jsonb_build_object('regulation_fields',
      '[{"label":"참가비","value":"64000"}]'::jsonb, 'regulation_notes','["보험"]'::jsonb,
      'regulation_body','본문','prize','상금','format','개인복식','description','요약')
   where id=tid;
  perform public.format_apply_staged(tid);
  perform 1 from public.tournaments where id=tid and format_status='formatted'
    and description='요약' and format_staged is null;
  assert found, 'apply_staged must copy staged to content';
  -- 원복
  update public.tournaments set format_status='pending', regulation_fields=null,
    regulation_notes=null, regulation_body=null, prize=null, format=null,
    description=null, formatted_at=null where id=tid;
end $$;
```
Expected: 오류 없음(assert 통과). ※ `is_admin()`이 service 컨텍스트에서 어떻게 평가되는지 확인 — service_role로 execute_sql 시 `is_admin()`이 false면 이 검증은 admin 세션 또는 `security definer` owner 권한 확인이 필요. 실패 시 검증만 admin 토큰으로 수행하고 RPC 자체는 정상.

- [ ] **Step 3: 커밋**

```bash
git add supabase/migrations/20260717*_format_staged_rpc.sql
git commit -m "feat(db): format_apply_staged/reject_staged RPC (admin 검수 반영)

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 어드민 검수 화면 + API + 라우팅

**Files:**
- Modify: `app/lib/services/admin_api.dart` (3개 메서드)
- Create: `app/lib/screens/admin/format_review_screen.dart`
- Modify: `app/lib/router.dart` (`/admin/format-review` 라우트, `app/lib/router.dart:142-168` 인접)
- Modify: `app/lib/screens/admin/admin_shell.dart` (`_items`에 항목)

**Interfaces:**
- Consumes: Task 2 RPC `format_apply_staged`/`format_reject_staged`.
- Produces: `AdminApi.formatReviewQueue()`, `AdminApi.applyStaged(id)`, `AdminApi.rejectStaged(id, reason)`; `FormatReviewScreen`.

- [ ] **Step 1: admin_api.dart 메서드 추가 (기존 `tournamentReviewQueue` 패턴)**

```dart
  Future<List<Map<String, dynamic>>> formatReviewQueue() async {
    final rows = await supabase
        .from('tournaments')
        .select('id, title, source_url, format_staged, format_flags')
        .eq('format_status', 'needs_review')
        .not('format_staged', 'is', null)
        .order('updated_at');
    return List<Map<String, dynamic>>.from(rows)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<bool> applyStaged(String id) async {
    final res = await supabase.rpc('format_apply_staged', params: {'p_tid': id});
    return res == true;
  }

  Future<bool> rejectStaged(String id, String reason) async {
    final res = await supabase
        .rpc('format_reject_staged', params: {'p_tid': id, 'p_reason': reason});
    return res == true;
  }
```

- [ ] **Step 2: 검수 화면 작성 (`format_review_screen.dart`)**

`moderation_screen.dart`의 목록+액션 패턴을 따라 작성. 각 항목: 제목, 원문 링크(source_url), staged 미리보기(regulation_fields를 label:value로), 승인/반려 버튼.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/admin_api.dart';
import '../../state/providers.dart';

final _formatReviewProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.read(adminApiProvider).formatReviewQueue();
});

class FormatReviewScreen extends ConsumerWidget {
  const FormatReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_formatReviewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('요강 검수')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (rows) => rows.isEmpty
            ? const Center(child: Text('검수할 요강이 없습니다.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ReviewCard(row: rows[i], ref: ref),
              ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final WidgetRef ref;
  const _ReviewCard({required this.row, required this.ref});

  @override
  Widget build(BuildContext context) {
    final staged = (row['format_staged'] as Map?)?.cast<String, dynamic>() ?? {};
    final fields = (staged['regulation_fields'] as List?) ?? [];
    final sourceUrl = row['source_url'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row['title'] as String? ?? '',
                style: Theme.of(context).textTheme.titleMedium),
            if (sourceUrl != null)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('원문 공고 보기'),
                onPressed: () => launchUrl(Uri.parse(sourceUrl)),
              ),
            const SizedBox(height: 8),
            ...fields.map((f) {
              final m = (f as Map).cast<String, dynamic>();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${m['label']}: ${m['value']}'),
              );
            }),
            if (staged['description'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('요약: ${staged['description']}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref.read(adminApiProvider).rejectStaged(
                        row['id'] as String, '검수 반려');
                    ref.invalidate(_formatReviewProvider);
                  },
                  child: const Text('반려'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await ref.read(adminApiProvider).applyStaged(row['id'] as String);
                    ref.invalidate(_formatReviewProvider);
                  },
                  child: const Text('승인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

`adminApiProvider`의 정확한 프로바이더명은 `state/providers.dart`에서 확인해 사용(admin_api를 제공하는 기존 provider). `url_launcher`는 pubspec에 이미 있으면 사용, 없으면 원문 링크를 `SelectableText`로 대체.

- [ ] **Step 3: 라우터 + 사이드바 등록**

`router.dart`의 `/admin/drafts` GoRoute 인접에 추가(import도):

```dart
GoRoute(
  path: '/admin/format-review',
  builder: (_, __) => const FormatReviewScreen(),
),
```

`admin_shell.dart`의 `_items`에 항목 추가(`/admin/drafts` 다음):

```dart
    (path: '/admin/format-review', label: '요강 검수', icon: Icons.rule_folder_outlined),
```

- [ ] **Step 4: analyze + 위젯 테스트**

Run: `cd app && flutter analyze`
Expected: No issues.

간단 위젯 테스트(`app/test/format_review_screen_test.dart`) — 빈 큐 렌더:
```dart
// FormatReviewScreen이 빈 데이터에서 '검수할 요강이 없습니다.' 표시.
// adminApiProvider를 override해 formatReviewQueue()가 []를 반환하도록 주입.
```
(기존 `app/test`의 provider override + pumpWidget 패턴을 따라 작성. adminApiProvider override로 빈 리스트 주입.)

Run: `cd app && flutter test test/format_review_screen_test.dart` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/lib/services/admin_api.dart app/lib/screens/admin/format_review_screen.dart \
        app/lib/router.dart app/lib/screens/admin/admin_shell.dart \
        app/test/format_review_screen_test.dart
git commit -m "feat(admin): 요강 검수 화면(staged 승인/반려) + /admin/format-review

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage(§12·13):** FormatStatus 타입화→Task1, staged 승인/반려 RPC(admin 전용)→Task2, 검수 화면(목록·원문대조·승인/반려)→Task3. 사용자 표시 무변경은 스펙 §13대로 tournament_detail 손대지 않음(명시).

**Placeholder scan:** `adminApiProvider`/패키지명/`url_launcher` 존재는 "기존 파일에서 확인 후 사용"으로 명시(프로젝트 고유). 위젯 테스트는 기존 provider-override 패턴 참조. 그 외 실코드.

**Type consistency:** `format_apply_staged(p_tid uuid)`/`format_reject_staged(p_tid uuid, p_reason text)` ↔ admin_api `params: {'p_tid':..., 'p_reason':...}` 일치. `format_staged` jsonb object(Plan 1 CHECK) ↔ RPC의 `s->'regulation_fields'` 등 ↔ Plan 3 complete가 저장한 `jsonb_build_object(...)` 키(regulation_fields/regulation_notes/regulation_body/prize/format/description)와 일치. `FormatStatus` 값이 Plan 1 CHECK 6개와 일치.
```
