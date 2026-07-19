# 대회 요강 정형화 파이프라인 — Plan 3: format-pending Edge Function Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 원문(raw_html)을 Gemini로 구조화해 요강 필드를 채우는 `format-pending` Edge Function을 만든다. claim→본문추출→구조화→민감값 검증→complete/reject/fail로 이어지며, 검증 실패·이상은 needs_review로, 기존 노출 대회는 검수 스테이징한다.

**Architecture:** embed-pending과 대칭. `format_pending_claim`으로 lease를 잡고, `crawl_documents.raw_html`을 개별 조회해 본문을 추출·절단한 뒤 Gemini `generateContent`(responseSchema)로 구조화한다. 민감값(금액·계좌·날짜)을 원문 substring으로 검증하고 마스킹된 플래그만 저장한다. 결과는 `format_pending_complete/reject/fail` RPC로 원자 반영한다.

**Tech Stack:** Deno, TypeScript, Gemini Generative Language API, Supabase JS(service client), pg_cron.

## Global Constraints

- Plan 1 선행: `format_pending_claim/complete/reject/fail` RPC 존재. **claim은 `status`, `formatted_at`도 반환**(Plan 1 보정 Task, 아래 참조).
- `format_flags`에는 원문 민감값(계좌번호 등)을 **절대 원문 그대로 넣지 않음** — `{code, field, masked}`만.
- config.toml에 `[functions.format-pending] verify_jwt = false`(cron 호출).
- TypeScript `any` 금지. CI warning=error.
- 배포: `supabase functions deploy format-pending --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json`.
- 커밋 끝: `Refs: JY-137` + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 0(선행): Plan 1 claim RPC에 status·formatted_at 반환 추가

**Files:**
- Modify: `supabase/migrations/20260717HHMMSS_tournament_format_pipeline.sql`(Plan 1 파일, claim RPC) — 아직 원격 적용 전이면 파일만 수정; 적용됐으면 `create or replace`로 재적용 후 `NOTIFY pgrst`.

**Interfaces:**
- Produces: `format_pending_claim(...)` 반환 table에 `status public.tournament_status, formatted_at timestamptz` 추가.

- [ ] **Step 1: claim RPC 반환 확장**

`returns table (...)`에 두 컬럼 추가, `stamped` returning과 최종 select에 반영:

```sql
returns table (
  tournament_id uuid, title text, sport public.sport, source text,
  claim_token uuid, document_id uuid, content_hash text,
  status public.tournament_status, formatted_at timestamptz
)
```
`stamped` CTE의 returning: `returning t.id, t.title, t.sport, t.source, t.format_claim_token, t.format_document_id, t.status, t.formatted_at`
최종 select: `select s.id, s.title, s.sport, s.source, s.format_claim_token, s.format_document_id, ld.chash, s.status, s.formatted_at from stamped s join latest_doc ld on ld.tid = s.id;`

- [ ] **Step 2: 재적용 + 검증**

Run(`execute_sql`, 수정된 claim 함수 전문) → `NOTIFY pgrst, 'reload schema';`
Run(`execute_sql`): `select tournament_id, status, formatted_at from public.format_pending_claim(1,15);` → 컬럼 반환 확인 후 상태 원복(Plan 1 Task4 Step4 방식).

---

### Task 1: gemini.ts — 구조화 출력 함수

**Files:**
- Modify: `supabase/functions/_shared/gemini.ts`
- Test: `supabase/functions/tests/gemini_structured_test.ts` (신규, JSON 파싱만 — 실제 API 미호출)

**Interfaces:**
- Produces: `generateStructured<T>(prompt: string, responseSchema: Record<string, unknown>, opts?: {systemInstruction?: string; temperature?: number; maxOutputTokens?: number}): Promise<T>` + `parseStructuredResponse<T>(json: unknown): T`(테스트 대상 순수 파서).

- [ ] **Step 1: 실패 테스트 — 응답 JSON 파서**

```typescript
import { assertEquals } from 'std/assert/mod.ts';
import { parseStructuredResponse } from '../_shared/gemini.ts';

Deno.test('parseStructuredResponse: candidates parts.text JSON 파싱', () => {
  const raw = { candidates: [{ content: { parts: [{ text: '{"a":1,"b":"x"}' }] } }] };
  const out = parseStructuredResponse<{ a: number; b: string }>(raw);
  assertEquals(out.a, 1);
  assertEquals(out.b, 'x');
});
```

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/gemini_structured_test.ts`
Expected: FAIL — `parseStructuredResponse` 미정의.

- [ ] **Step 3: 구현 (gemini.ts 하단에 추가)**

```typescript
export function parseStructuredResponse<T>(json: unknown): T {
  const j = json as { candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }> };
  const text = j.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
  if (!text) throw new Error('Gemini structured: empty response');
  return JSON.parse(text) as T;
}

export async function generateStructured<T>(
  prompt: string,
  responseSchema: Record<string, unknown>,
  opts: { systemInstruction?: string; temperature?: number; maxOutputTokens?: number } = {},
): Promise<T> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey()}`;
  const body: Record<string, unknown> = {
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: opts.temperature ?? 0.1,
      maxOutputTokens: opts.maxOutputTokens ?? 4096,
      thinkingConfig: { thinkingBudget: 0 },
      responseMimeType: 'application/json',
      responseSchema,
    },
  };
  if (opts.systemInstruction) body.systemInstruction = { parts: [{ text: opts.systemInstruction }] };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  return parseStructuredResponse<T>(await res.json());
}
```

- [ ] **Step 4: 통과 확인 + 커밋**

Run: `deno test --allow-env supabase/functions/tests/gemini_structured_test.ts` → PASS.
```bash
git add supabase/functions/_shared/gemini.ts supabase/functions/tests/gemini_structured_test.ts
git commit -m "feat(gemini): generateStructured (responseSchema JSON) 추가

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: format-pending 순수 헬퍼 (본문추출·검증·마스킹)

**Files:**
- Create: `supabase/functions/format-pending/logic.ts`
- Test: `supabase/functions/tests/format_pending_test.ts`

**Interfaces:**
- Produces:
  - `extractPlainText(html: string, maxLen: number): string` — HTML 태그·스크립트 제거, 공백 정리, maxLen 절단.
  - `RegulationResult`(Gemini 출력 타입): `{regulation_fields: {label:string;value:string}[]; regulation_notes: string[]; regulation_body: string; prize: string; format: string; description: string; confidence: number; unusual: boolean}`.
  - `FormatFlag`: `{code: string; field: string; masked: string}`.
  - `verifyAgainstSource(result: RegulationResult, sourceText: string): {ok: boolean; flags: FormatFlag[]}` — 금액/계좌/날짜 substring 대조.
  - `maskValue(v: string): string`.

- [ ] **Step 1: 실패 테스트**

```typescript
import { assert, assertEquals } from 'std/assert/mod.ts';
import { extractPlainText, maskValue, verifyAgainstSource } from '../format-pending/logic.ts';

Deno.test('extractPlainText: 태그 제거 + 절단', () => {
  const html = '<div>안녕<script>x=1</script> <b>세계</b></div>';
  assertEquals(extractPlainText(html, 100), '안녕 세계');
  assertEquals(extractPlainText('a'.repeat(50), 10).length, 10);
});

Deno.test('maskValue: 계좌/금액 뒷자리 마스킹', () => {
  assert(maskValue('123-4567-8901').includes('*'));
});

Deno.test('verifyAgainstSource: 원문에 없는 계좌/금액이면 flag', () => {
  const src = '참가비 64,000원 농협 302-1234-5678 입금';
  const good = verifyAgainstSource({
    regulation_fields: [{ label: '참가비', value: '64,000원' }, { label: '입금계좌', value: '농협 302-1234-5678' }],
    regulation_notes: [], regulation_body: '', prize: '', format: '', description: '', confidence: 0.9, unusual: false,
  }, src);
  assertEquals(good.ok, true);
  const bad = verifyAgainstSource({
    regulation_fields: [{ label: '입금계좌', value: '국민 999-8888-7777' }],
    regulation_notes: [], regulation_body: '', prize: '', format: '', description: '', confidence: 0.9, unusual: false,
  }, src);
  assertEquals(bad.ok, false);
  assert(bad.flags.length >= 1);
  assert(!bad.flags[0].masked.includes('8888')); // 마스킹됨
});

Deno.test('verifyAgainstSource: unusual=true면 flag', () => {
  const r = verifyAgainstSource({
    regulation_fields: [], regulation_notes: [], regulation_body: '', prize: '', format: '',
    description: '', confidence: 0.9, unusual: true,
  }, 'src');
  assertEquals(r.ok, false);
});
```

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/format_pending_test.ts`
Expected: FAIL — `logic.ts` 미정의.

- [ ] **Step 3: 구현 (`format-pending/logic.ts`)**

```typescript
export interface RegulationResult {
  regulation_fields: { label: string; value: string }[];
  regulation_notes: string[];
  regulation_body: string;
  prize: string;
  format: string;
  description: string;
  confidence: number;
  unusual: boolean;
}

export interface FormatFlag {
  code: string;
  field: string;
  masked: string;
}

export function extractPlainText(html: string, maxLen: number): string {
  const noScript = html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ');
  const noTags = noScript.replace(/<[^>]+>/g, ' ');
  const decoded = noTags
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
  const collapsed = decoded.replace(/\s+/g, ' ').trim();
  return collapsed.length > maxLen ? collapsed.slice(0, maxLen) : collapsed;
}

export function maskValue(v: string): string {
  const digits = v.replace(/\D/g, '');
  if (digits.length >= 4) {
    // 앞 2·뒤 0자리만 남기고 나머지 숫자를 * 로
    let shown = 0;
    return v.replace(/\d/g, (d) => (shown++ < 2 ? d : '*'));
  }
  return v.length <= 2 ? v : v.slice(0, 1) + '*'.repeat(v.length - 1);
}

// 원문 대조가 필요한 민감 토큰(금액·계좌·날짜)을 값에서 추출.
function sensitiveTokens(value: string): string[] {
  const tokens: string[] = [];
  for (const m of value.matchAll(/[0-9][0-9,]*\s*원/g)) tokens.push(m[0].replace(/\s+/g, ''));
  for (const m of value.matchAll(/\d{2,}-\d{2,}-\d{2,}/g)) tokens.push(m[0]); // 계좌
  for (const m of value.matchAll(/\d{4}[-.]\d{1,2}[-.]\d{1,2}/g)) tokens.push(m[0]); // 날짜
  return tokens;
}

// 원문 raw text에서 숫자만 비교하기 위한 정규화(구분자·공백 제거).
function digitsOnly(s: string): string {
  return s.replace(/[^0-9]/g, '');
}

export function verifyAgainstSource(
  result: RegulationResult,
  sourceText: string,
): { ok: boolean; flags: FormatFlag[] } {
  const flags: FormatFlag[] = [];
  if (result.unusual) flags.push({ code: 'unusual', field: '_model', masked: '' });
  if (typeof result.confidence === 'number' && result.confidence < 0.5) {
    flags.push({ code: 'low_confidence', field: '_model', masked: '' });
  }
  const srcDigits = digitsOnly(sourceText);
  for (const f of result.regulation_fields) {
    for (const tok of sensitiveTokens(f.value)) {
      if (!srcDigits.includes(digitsOnly(tok))) {
        flags.push({ code: 'not_in_source', field: f.label, masked: maskValue(tok) });
      }
    }
  }
  return { ok: flags.length === 0, flags };
}
```

- [ ] **Step 4: 통과 확인 + 커밋**

Run: `deno test --allow-env supabase/functions/tests/format_pending_test.ts` → PASS.
```bash
git add supabase/functions/format-pending/logic.ts supabase/functions/tests/format_pending_test.ts
git commit -m "feat(format-pending): 본문추출·민감값 검증·마스킹 순수 헬퍼

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: format-pending 오케스트레이션 (index.ts)

**Files:**
- Create: `supabase/functions/format-pending/index.ts`

**Interfaces:**
- Consumes: Plan 1 RPC `format_pending_claim(p_batch_size,p_lease_minutes)`(반환에 status/formatted_at 포함 — Task 0), `format_pending_complete(...13 args)`, `format_pending_reject(p_tid,p_token,p_flags,p_source_hash)`, `format_pending_fail(p_tid,p_token)`. Task 1 `generateStructured`, Task 2 `logic.ts`. `serviceClient`(supabase.ts), `requireServiceRoleOrAdmin`(auth.ts), `normalizeRegulationFields`/`capRegulationBody`(regulation.ts).

- [ ] **Step 1: 구현 (index.ts)**

```typescript
import { requireServiceRoleOrAdmin } from '../_shared/auth.ts';
import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import { serviceClient } from '../_shared/supabase.ts';
import { GEMINI_MODEL, generateStructured } from '../_shared/gemini.ts';
import { capRegulationBody, normalizeRegulationFields } from '../_shared/regulation.ts';
import { extractPlainText, type RegulationResult, verifyAgainstSource } from './logic.ts';

const BATCH_SIZE = 4;
const LEASE_MINUTES = 15;
const SOURCE_MAX = 12000; // Gemini 입력 상한
const BODY_MAX = 2500; // regulation_body 저장 상한(077 계약)

const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    regulation_fields: {
      type: 'array',
      items: {
        type: 'object',
        properties: { label: { type: 'string' }, value: { type: 'string' } },
        required: ['label', 'value'],
      },
    },
    regulation_notes: { type: 'array', items: { type: 'string' } },
    regulation_body: { type: 'string' },
    prize: { type: 'string' },
    format: { type: 'string' },
    description: { type: 'string' },
    confidence: { type: 'number' },
    unusual: { type: 'boolean' },
  },
  required: ['regulation_fields', 'regulation_notes', 'description', 'confidence', 'unusual'],
};

function buildPrompt(title: string, sourceText: string): string {
  return [
    '다음은 동호인 테니스/풋살 대회 공고 원문이다. 요강을 구조화하라.',
    '규칙: 원문에 없는 정보(금액·계좌·날짜 등)를 절대 만들지 말 것. 불명확하면 생략.',
    '값을 지어냈거나 형식이 처음 보는 구조면 unusual=true. 확신도는 confidence(0~1).',
    'regulation_fields는 {label,value} 배열(참가비/입금계좌/시상/일정/접수/경기방식 등),',
    'regulation_notes는 ※ 유의사항 문장 배열, regulation_body는 나머지 서술 본문,',
    'prize는 시상 요약, format은 경기방식 요약, description은 1~2줄 요약.',
    `대회명: ${title}`,
    '원문:',
    sourceText,
  ].join('\n');
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  const auth = await requireServiceRoleOrAdmin(req);
  if ('error' in auth) return auth.error;
  const supabase = serviceClient();
  const result = { processed: 0, needs_review: 0, failed: 0, errors: [] as string[] };

  const { data: claims, error: claimErr } = await supabase
    .rpc('format_pending_claim', { p_batch_size: BATCH_SIZE, p_lease_minutes: LEASE_MINUTES });
  if (claimErr) return errorResponse(`claim failed: ${claimErr.message}`, 500, result);
  const rows = (claims ?? []) as Array<{
    tournament_id: string; title: string; sport: string; source: string;
    claim_token: string; document_id: string; content_hash: string;
    status: string; formatted_at: string | null;
  }>;

  for (const c of rows) {
    try {
      const { data: doc } = await supabase
        .from('crawl_documents').select('raw_html').eq('id', c.document_id).maybeSingle();
      if (!doc?.raw_html) {
        await supabase.rpc('format_pending_fail', { p_tid: c.tournament_id, p_token: c.claim_token });
        result.failed++;
        continue;
      }
      const sourceText = extractPlainText(doc.raw_html as string, SOURCE_MAX);
      const parsed = await generateStructured<RegulationResult>(
        buildPrompt(c.title, sourceText), RESPONSE_SCHEMA,
      );
      const fields = normalizeRegulationFields(parsed.regulation_fields);
      const verdict = verifyAgainstSource(parsed, sourceText);

      if (fields.length === 0 || !verdict.ok) {
        await supabase.rpc('format_pending_reject', {
          p_tid: c.tournament_id, p_token: c.claim_token,
          p_flags: fields.length === 0
            ? [{ code: 'empty_fields', field: '_all', masked: '' }, ...verdict.flags]
            : verdict.flags,
          p_source_hash: c.content_hash,
        });
        result.needs_review++;
        continue;
      }

      // 스테이징 판정: 이미 노출 중(published/closed)인데 최초 정형화면 검수 스테이징.
      const stage = (c.status === 'published' || c.status === 'closed') && c.formatted_at === null;
      const { error: compErr } = await supabase.rpc('format_pending_complete', {
        p_tid: c.tournament_id, p_token: c.claim_token, p_document_id: c.document_id,
        p_source_hash: c.content_hash,
        p_regulation_fields: fields,
        p_regulation_notes: parsed.regulation_notes ?? [],
        p_regulation_body: capRegulationBody(parsed.regulation_body, BODY_MAX) || null,
        p_prize: parsed.prize || null,
        p_format: parsed.format || null,
        p_description: parsed.description || null,
        p_model: GEMINI_MODEL,
        p_flags: verdict.flags.length ? verdict.flags : null,
        p_stage: stage,
      });
      if (compErr) {
        result.errors.push(`complete ${c.tournament_id}: ${compErr.message}`);
        await supabase.rpc('format_pending_fail', { p_tid: c.tournament_id, p_token: c.claim_token });
        result.failed++;
      } else if (stage) result.needs_review++;
      else result.processed++;
    } catch (e) {
      result.errors.push(`${c.tournament_id}: ${(e as Error).message}`);
      await supabase.rpc('format_pending_fail', { p_tid: c.tournament_id, p_token: c.claim_token });
      result.failed++;
    }
  }
  return jsonResponse(result);
});
```

- [ ] **Step 2: lint/타입 확인**

Run: `deno check supabase/functions/format-pending/index.ts`
Expected: 타입 에러 없음(any 없음). `cors.ts`의 `preflight/jsonResponse/errorResponse` 시그니처는 embed-pending과 동일하게 사용.

- [ ] **Step 3: 커밋**

```bash
git add supabase/functions/format-pending/index.ts
git commit -m "feat(format-pending): claim→Gemini 구조화→검증→complete/reject/fail 오케스트레이션

- 스테이징: published/closed & formatted_at IS NULL → 검수(needs_review)
- 검증 실패/빈 필드 → reject, 예외 → fail

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: config.toml + pg_cron 등록 + 배포

**Files:**
- Modify: `supabase/config.toml`
- Modify: 마이그레이션(신규 작은 파일) 또는 `execute_sql`로 cron 등록.

- [ ] **Step 1: config.toml에 verify_jwt=false 추가**

`[functions.embed-pending]` 블록 인접에 추가:

```toml
[functions.format-pending]
verify_jwt = false
```

- [ ] **Step 2: 배포**

Run:
```bash
cd /Users/ssfak/Documents/01-github/AllRound
supabase functions deploy format-pending --project-ref bsjdgwmveokanclqwtvx --import-map supabase/functions/import_map.json
```
Expected: 배포 성공.

- [ ] **Step 3: 수동 1회 호출로 스모크 테스트**

`execute_sql`로 pending 1건 상태 확인 후, 함수 URL을 service_role로 호출(또는 `select net.http_post(...)` 방식이 프로젝트에 있으면 그걸로). 반환 JSON에 `processed/needs_review/failed` 확인. 실패 시 로그: `get_logs`.

- [ ] **Step 4: pg_cron 등록 (embed-pending과 offset)**

Run(`execute_sql`, 기존 crawl-dispatch/embed-pending cron 등록 방식 확인 후 동일 패턴):
```sql
select cron.schedule(
  'format-pending',
  '2-59/5 * * * *',  -- embed-pending(*/5)과 2분 offset
  $$select net.http_post(
      url := '<project functions url>/format-pending',
      headers := jsonb_build_object('Authorization', 'Bearer <INTERNAL_CRON_JWT>', 'Content-Type','application/json'),
      body := '{}'::jsonb
  )$$
);
```
Note: `net.http_post` URL/JWT 조립은 기존 embed-pending cron 등록 마이그레이션을 그대로 참고해 동일 방식으로. (프로젝트에 `invoke_edge_function()` 헬퍼가 있으면 그것 사용.)

- [ ] **Step 5: 커밋**

```bash
git add supabase/config.toml
git commit -m "chore(format-pending): verify_jwt=false + pg_cron 등록(*/5 offset)

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage(§9·10·11):** 본문추출→Task2, Gemini 구조화→Task1·3, normalize+빈배열 reject→Task3, 민감값 substring 검증→Task2, 마스킹(원문값 미노출)→Task2 maskValue+verify, 스테이징 판정→Task3, complete/reject/fail 분기→Task3, cron/config→Task4.

**Placeholder scan:** cron 등록의 URL/JWT는 "기존 embed-pending cron 방식 참고"로 명시(프로젝트 고유 조립). 그 외 실코드. `cors.ts` 시그니처는 embed-pending과 동일 사용.

**Type consistency:** claim 반환(Task 0로 status/formatted_at 추가) ↔ index.ts `rows` 타입 일치. complete 13개 인자(p_tid,p_token,p_document_id,p_source_hash,p_regulation_fields,p_regulation_notes,p_regulation_body,p_prize,p_format,p_description,p_model,p_flags,p_stage) ↔ Plan 1 시그니처 순서·타입 일치. `RegulationResult`가 RESPONSE_SCHEMA와 필드 일치. `normalizeRegulationFields`는 `{label,value}[]` 반환(regulation.ts).
