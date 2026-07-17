# 대회 요강 정형화 파이프라인 — Plan 2: 크롤러 수정 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 크롤러가 요강 콘텐츠(description/prize/format/regulation_*)를 덮어쓰지 않게 하고(정형화는 LLM 전담), 재크롤로 원문이 바뀌면 정형화 큐에 다시 넣고, 원문 없는 신규 행은 skipped로 넣는다.

**Architecture:** `upsertTournament`의 update 경로를 "값이 정의된 필드만 payload" 규약으로 통일하고, 새 `content_hash`가 기존 `format_source_hash`와 다르면 `format_status='pending'`으로 재큐한다. 파서(gnuboard/kato)는 요강 관련 필드를 방출하지 않도록 축소한다.

**Tech Stack:** Deno, TypeScript, Supabase JS client. 테스트는 기존 `crawler_upsert_preserve_test.ts`의 fake client 패턴.

## Global Constraints

- Plan 1(DB)이 선행: `tournaments.format_status/format_source_hash/format_claim_token/claimed_at` 컬럼 존재 전제.
- 파서는 `description/prize/format/regulation_fields/regulation_notes/regulation_body`를 **`undefined`로 두어 방출하지 않음**(값을 내면 upsert가 덮어씀; `null`은 와이프이므로 금지).
- TypeScript `any` 금지. CI가 warning도 에러 처리.
- 테스트: `deno test --allow-env supabase/functions/tests/crawler_upsert_preserve_test.ts`.
- 커밋 메시지 끝: `Refs: JY-137` + `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: upsert 경로 — prize/format 가드 + 재크롤 재큐 + skipped

**Files:**
- Modify: `supabase/functions/_shared/crawler.ts` (`upsertTournament` update/insert 경로, `saveRawDocument` 인접)
- Test: `supabase/functions/tests/crawler_upsert_preserve_test.ts`

**Interfaces:**
- Consumes: `sha256Hex(rawHtml)`(crawler.ts 내 기존 함수, `saveRawDocument`가 사용), Plan 1 컬럼 `format_status/format_source_hash/format_claim_token/claimed_at`.
- Produces: update payload가 `prize/format`을 `!== undefined`일 때만 포함. 새 content_hash ≠ 기존 format_source_hash → `format_status='pending'` 재설정. insert에서 rawHtml 없으면 `format_status='skipped'`.

- [ ] **Step 1: 실패 테스트 추가 — 재크롤이 prize/format을 지우지 않는다**

`crawler_upsert_preserve_test.ts`에 케이스 추가(기존 fake client 패턴 사용, `EXISTING_ROW`에 `format_source_hash` 포함하도록 확장):

```typescript
Deno.test('upsert: 파서가 prize/format 미방출(undefined)이면 기존 값 보존', async () => {
  const captured: CapturedUpdate = { payload: {} };
  const audit = makeAudit(
    { ...EXISTING_ROW, format_source_hash: 'oldhash' },
    (payload) => (captured.payload = payload),
  );
  const t: CrawlerTournament = {
    title: '기존 대회', start_date: '2026-07-04', eligible_grades: [],
    source_url: 'https://x/1',
    // description/prize/format/regulation_* 미설정(undefined) — 파서가 요강 방출 안 함
  };
  await upsertTournament(audit, 'tennis', t); // rawHtml 미전달
  assert(!('prize' in captured.payload), 'prize를 payload에 넣지 않아야 함');
  assert(!('format' in captured.payload), 'format를 payload에 넣지 않아야 함');
  assert(!('description' in captured.payload), 'description 미방출 시 payload 제외');
});
```

`makeAudit` 헬퍼가 없으면 기존 파일의 fake client 구성 방식을 그대로 재사용해 `EXISTING_ROW`에 `format_source_hash`를 추가한다.

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/crawler_upsert_preserve_test.ts`
Expected: FAIL — 현재 코드가 `prize: t.prize ?? null, format: t.format ?? null`을 항상 payload에 넣으므로 `'prize' in payload`가 true.

- [ ] **Step 3: update 경로 수정 — prize/format 가드 + 재큐**

`upsertTournament` update 분기에서, `existing` select에 `format_source_hash` 추가:

```typescript
const { data: existing } = await audit.supabase
  .from('tournaments')
  .select(
    'id, title, start_date, application_deadline, eligible_grades, region, manual_description, format_source_hash',
  )
  .eq('source', audit.source)
  .eq('source_url', t.source_url)
  .maybeSingle();
```

updatePayload 구성에 prize/format 가드 추가(description/regulation_*와 동일 규약):

```typescript
if (t.prize !== undefined) updatePayload.prize = t.prize;
if (t.format !== undefined) updatePayload.format = t.format;
```

그리고 update 최종 `.update({...})`에서 `prize`/`format`을 **고정 필드에서 제거**(위 가드가 대체). 재큐 로직 추가(rawHtml 있을 때 새 해시 비교):

```typescript
if (rawHtml) {
  const newHash = await sha256Hex(rawHtml);
  if (existing.format_source_hash && existing.format_source_hash !== newHash) {
    updatePayload.format_status = 'pending';
    updatePayload.format_claim_token = null;
    updatePayload.claimed_at = null;
  }
}
```

update 호출의 고정 필드 목록은 다음으로 축소(entry_fee는 기존대로 유지, prize/format 제거):

```typescript
.update({
  ...updatePayload,
  start_date: t.start_date,
  end_date: t.end_date ?? null,
  application_deadline: t.application_deadline ?? null,
  region: t.region ?? null,
  region_code: regionCode,
  location: t.location ?? null,
  entry_fee: t.entry_fee ?? null,
})
```

- [ ] **Step 4: insert 경로 — skipped + prize/format/regulation null 방출 유지**

insert payload에서 rawHtml 유무로 format_status 지정. `description/regulation_*/prize/format`은 파서가 미방출이면 `?? null`로 null 저장되나, 신규 insert는 어차피 정형화 대상이므로 콘텐츠는 비어도 무방. format_status만 정확히:

```typescript
.insert({
  sport,
  title: t.title,
  organizer: t.organizer ?? null,
  description: t.description ?? null,
  start_date: t.start_date,
  end_date: t.end_date ?? null,
  application_deadline: t.application_deadline ?? null,
  region: t.region ?? null,
  region_code: regionCode,
  location: t.location ?? null,
  eligible_grades: t.eligible_grades,
  division_label_local: t.division_label_local ?? null,
  entry_fee: t.entry_fee ?? null,
  prize: t.prize ?? null,
  format: t.format ?? null,
  regulation_fields: t.regulation_fields ?? null,
  regulation_notes: t.regulation_notes ?? null,
  regulation_body: t.regulation_body ?? null,
  source: audit.source,
  source_url: t.source_url,
  status: 'draft',
  format_status: rawHtml ? 'pending' : 'skipped',
})
```

- [ ] **Step 5: 테스트 통과 확인 + 재큐 테스트 추가**

재큐 케이스 추가:

```typescript
Deno.test('upsert: 재크롤로 content_hash 바뀌면 format_status=pending 재설정', async () => {
  const captured: CapturedUpdate = { payload: {} };
  const audit = makeAudit(
    { ...EXISTING_ROW, format_source_hash: 'oldhash' },
    (payload) => (captured.payload = payload),
  );
  const t: CrawlerTournament = {
    title: '기존 대회', start_date: '2026-07-04', eligible_grades: [], source_url: 'https://x/1',
  };
  await upsertTournament(audit, 'tennis', t, '<html>바뀐 원문</html>');
  assertEquals(captured.payload.format_status, 'pending');
  assertEquals(captured.payload.format_claim_token, null);
});
```

Run: `deno test --allow-env supabase/functions/tests/crawler_upsert_preserve_test.ts`
Expected: PASS (모든 케이스). ※ rawHtml 전달 시 `saveRawDocument` 경로를 타므로 fake client가 `crawl_documents` upsert도 받도록 기존 파일의 모킹을 확장(기존 파일 주석 참고).

- [ ] **Step 6: 커밋**

```bash
cd /Users/ssfak/Documents/01-github/AllRound
git add supabase/functions/_shared/crawler.ts supabase/functions/tests/crawler_upsert_preserve_test.ts
git commit -m "feat(crawler): prize/format undefined 가드 + 재크롤 hash 재큐 + skipped

- update 경로에서 prize/format도 !== undefined일 때만 payload (AI 정형화 결과 보존)
- content_hash != format_source_hash면 format_status=pending 재큐
- rawHtml 없는 insert는 format_status=skipped

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: gnuboard 파서 — 요강 필드 방출 제거

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts` (description/regulation_fields/regulation_notes/regulation_body/prize/format 조립부)
- Test: `supabase/functions/tests/crawler_extract_test.ts` (해당 파서 기대값 조정)

**Interfaces:**
- Produces: 파서가 반환하는 `CrawlerTournament`에서 `description/prize/format/regulation_*`를 **설정하지 않음**(undefined). 메타(title/start_date/end_date/application_deadline/region/location/eligible_grades/division_label_local/organizer/entry_fee/source_url)는 유지.

- [ ] **Step 1: 기존 파서 테스트에서 요강 기대 제거(실패 유도)**

`crawler_extract_test.ts`에서 gnuboard 파서 결과의 `description`/`regulation_fields` 등을 검증하는 assert를 "미방출(undefined)" 검증으로 교체:

```typescript
assertEquals(result.description, undefined);
assertEquals(result.regulation_fields, undefined);
assertEquals(result.regulation_body, undefined);
assertEquals(result.prize, undefined);
assertEquals(result.format, undefined);
// 메타는 유지 검증
assertEquals(result.start_date, '2026-05-30');
```

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/crawler_extract_test.ts`
Expected: FAIL — 현재 파서가 description/regulation_* 조립.

- [ ] **Step 3: 파서에서 요강 조립 제거**

`gnuboard_sub5_5_contest.ts`에서 다음을 제거하고 반환 객체에서 해당 키를 뺀다:
- `rawBody`/`MAX_DESC_BODY`/`trimmedBody`/`descParts`/`metaLine`/`description` 계산 블록 전체.
- `regulationFields`/`regulationNotes`/`regulation_body` 추출 블록.
- 반환 `CrawlerTournament`에서 `description`, `regulation_fields`, `regulation_notes`, `regulation_body`, `prize`, `format` 키 삭제(설정하지 않음).

유지: title, start_date, end_date, application_deadline, region, location, eligible_grades, division_label_local, organizer, entry_fee, source_url. (엔트리피/장소/주최 추출 헬퍼는 그대로.)

- [ ] **Step 4: 통과 확인**

Run: `deno test --allow-env supabase/functions/tests/crawler_extract_test.ts`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/gnuboard_sub5_5_contest.ts supabase/functions/tests/crawler_extract_test.ts
git commit -m "refactor(crawler): gnuboard 파서 요강 조립 제거 (LLM 정형화로 이관)

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: kato 파서 — description 메타라인 조립 제거

**Files:**
- Modify: `supabase/functions/_shared/crawler/parsers/kato_openlist.ts` (`buildTournament`의 `descParts`/`description`)
- Test: `supabase/functions/tests/kato_parser_test.ts`

**Interfaces:**
- Produces: `buildTournament`가 반환하는 객체에서 `description` 제거(undefined). 나머지(title/start_date/end_date/region/location/eligible_grades/division_label_local/organizer/entry_fee/source_url) 유지.

- [ ] **Step 1: kato 테스트에서 description 기대를 undefined로**

`kato_parser_test.ts`에서 `buildTournament`/파서 결과의 `description` 검증을 교체:

```typescript
assertEquals(t.description, undefined);
// 메타 유지
assertEquals(t.location, '공주시립실내테니스장');
assertEquals(t.organizer, '(사) 한국테니스발전협의회(KATO)');
```

- [ ] **Step 2: 실패 확인**

Run: `deno test --allow-env supabase/functions/tests/kato_parser_test.ts`
Expected: FAIL — `description`이 `참가부서: … | 대회일: … | 장소: … | 주최: …`.

- [ ] **Step 3: `buildTournament`에서 description 조립 제거**

`kato_openlist.ts`의 `buildTournament`에서 `descParts` 배열과 `description: descParts.join(' | ') || undefined`를 삭제하고, 반환 객체에서 `description` 키를 뺀다. 나머지 필드는 유지.

- [ ] **Step 4: 통과 확인**

Run: `deno test --allow-env supabase/functions/tests/kato_parser_test.ts`
Expected: PASS.

- [ ] **Step 5: 커밋**

```bash
git add supabase/functions/_shared/crawler/parsers/kato_openlist.ts supabase/functions/tests/kato_parser_test.ts
git commit -m "refactor(crawler): kato 파서 description 메타라인 조립 제거 (LLM 정형화로 이관)

Refs: JY-137

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage(§8):** prize/format 가드→Task1 Step3, 규칙기반 파싱 제거→Task2·3, 재크롤 재큐→Task1 Step3, skipped 전환→Task1 Step4, 회귀 테스트→Task1 Step1·5.

**Placeholder scan:** `makeAudit` 헬퍼는 기존 테스트 파일의 fake client 구성을 재사용(파일 내 실제 형태 확인 지시). 그 외 실코드. 파서 제거는 "해당 블록 삭제 + 반환 키 제외"로 구체.

**Type consistency:** `CrawlerTournament`의 description/prize/format/regulation_*는 optional이므로 미설정=undefined 유효. Task1의 재큐 필드(format_status/format_claim_token/claimed_at)는 Plan 1 컬럼과 일치. `sha256Hex`는 crawler.ts 기존 함수 재사용.
