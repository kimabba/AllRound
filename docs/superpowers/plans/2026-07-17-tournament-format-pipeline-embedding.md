# 대회 요강 정형화 파이프라인 — Plan 4: 임베딩 경합 방지 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** format-pending이 콘텐츠를 갱신하는 사이 embed-pending이 옛 벡터로 임베딩을 덮어써 stale 벡터가 영구 잔존하는 경합을, `embedding_input_revision` optimistic write로 차단한다. 정형화 전(pending/processing) 행은 임베딩하지 않는다.

**Architecture:** embed-pending의 tournaments select에 `embedding_input_revision`을 함께 읽고, 완료 UPDATE에 `.eq('embedding_input_revision', revisionRead)` 조건을 걸어 그새 콘텐츠가 바뀌었으면(트리거가 revision++) 쓰기를 스킵한다. 선별에서 `format_status` pending/processing을 제외한다.

**Tech Stack:** Deno, TypeScript, Supabase JS client.

## Global Constraints

- Plan 1 선행: 트리거 `invalidate_tournament_embedding`가 콘텐츠 변경 시 `embedding_input_revision++`, 신규 컬럼 `embedding_input_revision bigint`, `format_status` 존재 전제.
- `rule_articles` 경로는 건드리지 않음(tournaments만).
- TypeScript `any` 금지. CI가 warning도 에러 처리.
- 배포: `supabase functions deploy embed-pending --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json`.
- 커밋 끝: `Refs: JY-137` + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: 선별에 미정형 제외 필터 + revision 읽기

**Files:**
- Modify: `supabase/functions/embed-pending/index.ts` (tournaments select, `PendingTournament` 인터페이스)
- Test: `supabase/functions/tests/embed_pending_revision_test.ts` (신규)

**Interfaces:**
- Consumes: Plan 1 컬럼 `embedding_input_revision`, `format_status`.
- Produces: `PendingTournament`에 `embedding_input_revision: number`. select가 pending/processing 제외 + revision 포함.

- [ ] **Step 1: 실패 테스트 — 선별 쿼리 빌더가 필터·컬럼을 포함하는지**

선별 로직을 순수 함수로 분리해 테스트 가능하게 한다. `embed-pending/index.ts`에 export 함수 추가 예정:

```typescript
// supabase/functions/tests/embed_pending_revision_test.ts
import { assert, assertEquals } from 'std/assert/mod.ts';
import { buildTournamentSelect } from '../embed-pending/index.ts';

Deno.test('선별: pending/processing 제외 + revision 컬럼 포함', () => {
  const spec = buildTournamentSelect();
  assert(spec.columns.includes('embedding_input_revision'));
  assertEquals(spec.excludeFormatStatus, ['pending', 'processing']);
  assertEquals(spec.onlyStatus, 'published');
});
```

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/embed_pending_revision_test.ts`
Expected: FAIL — `buildTournamentSelect` 미정의.

- [ ] **Step 3: select 스펙 함수 + 인터페이스 수정**

`embed-pending/index.ts`:

```typescript
export interface TournamentSelectSpec {
  columns: string;
  onlyStatus: 'published';
  excludeFormatStatus: ['pending', 'processing'];
}

export function buildTournamentSelect(): TournamentSelectSpec {
  return {
    columns:
      'id, title, description, region, format, organizer, regulation_fields, regulation_body, embedding_input_revision',
    onlyStatus: 'published',
    excludeFormatStatus: ['pending', 'processing'],
  };
}
```

`PendingTournament`에 필드 추가:

```typescript
interface PendingTournament {
  id: string;
  title: string;
  description: string | null;
  region: string | null;
  format: string | null;
  organizer: string | null;
  regulation_fields: unknown;
  regulation_body: string | null;
  embedding_input_revision: number;
}
```

tournaments 조회부를 스펙으로 교체:

```typescript
const sel = buildTournamentSelect();
const { data: pending } = await supabase
  .from('tournaments')
  .select(sel.columns)
  .is('embedding', null)
  .eq('status', sel.onlyStatus)
  .not('format_status', 'in', '("pending","processing")')
  .limit(BATCH_SIZE);
```

- [ ] **Step 4: 통과 확인**

Run: `deno test --allow-env supabase/functions/tests/embed_pending_revision_test.ts`
Expected: PASS.

---

### Task 2: 완료 UPDATE에 revision optimistic 조건

**Files:**
- Modify: `supabase/functions/embed-pending/index.ts` (tournaments update 루프)
- Test: `supabase/functions/tests/embed_pending_revision_test.ts`

**Interfaces:**
- Produces: 임베딩 저장 UPDATE가 `.eq('embedding_input_revision', revisionRead)`로 revision 일치 시에만 쓰기.

- [ ] **Step 1: 실패 테스트 — update가 revision 조건을 건다**

fake client로 update 체인의 `.eq` 인자를 캡처:

```typescript
Deno.test('update: 읽은 revision과 일치 조건으로만 임베딩 저장', async () => {
  const eqCalls: Array<[string, unknown]> = [];
  const fakeClient = makeEmbedFakeClient(
    [{ id: 't1', title: '대회', description: null, region: null, format: null,
       organizer: null, regulation_fields: null, regulation_body: null,
       embedding_input_revision: 7 }],
    (col, val) => eqCalls.push([col, val]),
  );
  await runTournamentEmbedding(fakeClient, async () => [[0.1, 0.2]]);
  assert(eqCalls.some(([c, v]) => c === 'id' && v === 't1'));
  assert(eqCalls.some(([c, v]) => c === 'embedding_input_revision' && v === 7));
});
```

`makeEmbedFakeClient`와 `runTournamentEmbedding`은 이 Task에서 도입(아래). embedBatch를 주입 가능하게 분리.

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/embed_pending_revision_test.ts`
Expected: FAIL — `runTournamentEmbedding` 미정의.

- [ ] **Step 3: 임베딩 루프를 주입 가능 함수로 추출 + revision 조건**

`embed-pending/index.ts`에서 tournaments 임베딩 처리를 함수로 추출(embedBatch를 인자로 주입해 테스트 가능):

```typescript
type EmbedFn = (texts: string[]) => Promise<number[][]>;

export async function runTournamentEmbedding(
  supabase: SupabaseClient,
  embed: EmbedFn,
): Promise<{ processed: number; skipped: number; errors: string[] }> {
  const out = { processed: 0, skipped: 0, errors: [] as string[] };
  const sel = buildTournamentSelect();
  const { data: pending } = await supabase
    .from('tournaments')
    .select(sel.columns)
    .is('embedding', null)
    .eq('status', sel.onlyStatus)
    .not('format_status', 'in', '("pending","processing")')
    .limit(BATCH_SIZE);
  if (!pending || pending.length === 0) return out;

  const rows = pending as unknown as PendingTournament[];
  const texts = rows.map((t) => tournamentText(t));
  const embeddings = await embed(texts);
  const now = new Date().toISOString();
  for (let i = 0; i < rows.length; i++) {
    const { data, error } = await supabase
      .from('tournaments')
      .update({ embedding: toVectorLiteral(embeddings[i]), embedding_updated_at: now })
      .eq('id', rows[i].id)
      .eq('embedding_input_revision', rows[i].embedding_input_revision) // optimistic: 그새 바뀌면 0행
      .select('id');
    if (error) out.errors.push(`tournament ${rows[i].id}: ${error.message}`);
    else if (!data || data.length === 0) out.skipped++; // revision 변경 → 다음 사이클 재생성
    else out.processed++;
  }
  return out;
}
```

`Deno.serve` 핸들러의 tournaments try 블록을 `runTournamentEmbedding(supabase, embedBatch)` 호출로 교체하고 결과를 `result.tournaments_processed`에 반영. `SupabaseClient` 타입은 `@supabase/supabase-js` import(기존 supabase.ts 참고).

- [ ] **Step 4: 통과 확인**

Run: `deno test --allow-env supabase/functions/tests/embed_pending_revision_test.ts`
Expected: PASS. (경합 스킵 케이스: fake client의 update가 0행 반환하도록 구성한 별도 테스트도 추가해 `skipped++` 검증.)

- [ ] **Step 5: 경합 스킵 테스트 추가**

```typescript
Deno.test('경합: update가 0행이면 skipped 처리(덮어쓰지 않음)', async () => {
  const client = makeEmbedFakeClient(
    [{ id: 't1', title: '대회', description: null, region: null, format: null,
       organizer: null, regulation_fields: null, regulation_body: null,
       embedding_input_revision: 7 }],
    () => {}, { updateReturnsRows: 0 },
  );
  const r = await runTournamentEmbedding(client, async () => [[0.1]]);
  assertEquals(r.skipped, 1);
  assertEquals(r.processed, 0);
});
```

Run: `deno test --allow-env supabase/functions/tests/embed_pending_revision_test.ts`
Expected: PASS.

- [ ] **Step 6: 배포 + 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
supabase functions deploy embed-pending --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json
git add supabase/functions/embed-pending/index.ts supabase/functions/tests/embed_pending_revision_test.ts
git commit -m "fix(embed): revision optimistic write + 미정형 제외 (stale 임베딩 경합 차단)

- select에 embedding_input_revision 포함, format_status pending/processing 제외
- 완료 UPDATE에 .eq('embedding_input_revision', read) → 그새 콘텐츠 변경 시 스킵
- tournaments 임베딩 루프를 runTournamentEmbedding으로 추출(테스트 주입)

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage(§7):** revision optimistic write→Task2 Step3, 미정형 제외 필터→Task1 Step3, 경합 스킵 검증→Task2 Step5.

**Placeholder scan:** `makeEmbedFakeClient`는 이 Plan에서 도입하는 테스트 헬퍼(update 체인 `.eq`/`.select` 캡처, `updateReturnsRows` 옵션). 구현은 기존 `crawler_upsert_preserve_test.ts`의 체인 모킹 방식을 따른다. 그 외 실코드.

**Type consistency:** `buildTournamentSelect().columns`에 `embedding_input_revision` 포함 ↔ `PendingTournament.embedding_input_revision: number` ↔ update `.eq('embedding_input_revision', rows[i].embedding_input_revision)` 일치. `runTournamentEmbedding` 반환 `{processed,skipped,errors}`를 핸들러가 소비.
