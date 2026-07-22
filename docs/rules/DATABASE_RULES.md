# Database Rules

Load this when touching `supabase/migrations/`, SQL functions, RLS, RPC, pg_cron, pg_net, or pgvector search.

## Schema rules

- Use explicit types for every column.
- Prefer `text` over `varchar` unless there is a specific constraint reason.
- Reusable enums should use `create type`.
- New tables must enable RLS and include policies in the same migration.
- Add indexes for expected search/filter paths.

## RLS and authorization

- RLS must be the final data access boundary.
- Admin checks should use a reviewed SECURITY DEFINER helper such as `is_admin()`.
- Service-role usage should be isolated to Edge Functions and cron workers; never expose it to the client.

## RPC rules

- Eligibility and filtering rules that must be consistent should live in SQL/RPC, not in Flutter.
- `tournaments_for_user`-style functions must prevent cross-sport grade matching.
- Filters that affect result membership should be applied before pagination.

## Cron and workers

- `embed-pending`, `notify-cron`, and crawler jobs may have `verify_jwt=false`, but still need invocation protection.
- Store cron invocation URL/key via DB GUC only in secure environments.
- Workers should be idempotent where practical.

## pgvector / embeddings

- Tournament/rule content changes should invalidate embeddings by setting `embedding = null`.
- Embedding workers recompute pending rows.
- Vector dimensions must match `gemini-embedding-001` usage: 768d.

## 마이그레이션 배포 (머지 ≠ 프로덕션 적용)

> ⚠️ **PR을 머지해도 마이그레이션은 프로덕션에 자동 적용되지 않는다.** CI(`ci.yml`)는 테스트만 돌고 `supabase db push`를 실행하지 않는다. 머지 후 누군가 수동으로 적용해야 앱에 반영된다. (사고 사례 2026-06-10: `051`/`052`/`053`이 머지 후에도 프로덕션에 없어 앱에 미반영.)

### 현행 정책 — 수동 적용 + 게이트

1. **PR 작성 시**: PR 템플릿의 "마이그레이션 배포" 섹션을 채운다 — 포함 파일, 프로덕션 적용 담당, 적용 시점.
2. **PR 본문의 변경 범위 설명은 실제와 일치해야 한다.** "DB 변경 없음"인데 마이그레이션이 포함되면 안 된다.
3. **머지 직후 즉시** 담당자가 `supabase db push` 로 적용한다 (지연하면 "머지됐는데 앱엔 안 보임" 함정 발생).
4. 적용 후 실제 호출/조회로 반영을 확인한다 (의존 RPC·뷰·Edge·앱 모델 동반 갱신은 마이그레이션 의존 객체 규칙 참고).

> 🚫 **`apply_migration` / `execute_sql` 로 스키마를 적용하지 않는다** (2026-07-22 결정).
> `apply_migration` 은 **호출 시각**으로 version 을 새로 만들고 파일명을 name 안에 밀어 넣기
> 때문에, 적용할 때마다 이력이 파일명과 어긋난다. 그렇게 83건이 어긋나 `db push` 가 통째로
> 막혔던 것이 JY-116 이다. 2026-07-22 에 이력 127행을 파일명 기준으로 정합화해 해소했다
> (경위·대응표: `docs/db/migration-history-repair-20260722.md`).
>
> 긴급 상황에서 부득이 `execute_sql` 로 직접 실행했다면, **같은 세션 안에서**
> `supabase migration repair --linked --status applied <파일 version>` 으로 이력을 맞춰 둔다.
> 안 맞추면 다음 `db push` 가 그 파일을 다시 실행한다.

### 데이터 시드 컨벤션

- 사용자에게 노출되는 데이터(대회 등)는 `published` 상태로 **직접 INSERT 하지 않는다.**
- 반드시 **어드민 검수 화면(검수 큐)** 을 거쳐 등록한다. 검수 큐 우회는 데이터 출처·품질 보증을 깨뜨린다.
- 불가피한 직접 시드는 PR에 출처를 명시하고 리뷰에서 명시적으로 승인받는다.

### 향후 과제

- 스테이징 환경 확보 후, CI 자동 `supabase db push`(머지 시) 또는 `workflow_dispatch` 수동 트리거로 업그레이드 검토. 현재는 프로덕션 직결·사람 게이트 부재·시크릿 저장 위험 때문에 보류 (JY-57 결정).

## Checks

- For migration changes, run `supabase db reset` when Docker/Supabase CLI are available.
- Add SQL smoke fixtures for RLS/RPC behavior when changing domain-critical logic.
- After merging a migration PR, apply it to production immediately (see "마이그레이션 배포" above). Merge does not deploy.
