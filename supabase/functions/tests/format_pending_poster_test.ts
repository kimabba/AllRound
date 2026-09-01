// format_pending_poster_test.ts
// P6 포스터 보완 단계 로직 테스트 — 네트워크 없음(fetch/Gemini/sleep 주입 seam).
// 안전 원칙 검증 포함: 포스터 추출 결과는 라벨·notice·flag 로 출처가 표기되고,
// 빈 값(이미지에 없음)은 절대 항목으로 만들지 않는다.

import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  normalizeRegulationDocument,
  type RegulationDocument,
} from '../_shared/regulation_document.ts';
import type { InlineImage } from '../_shared/gemini.ts';
import {
  appendPosterSection,
  buildPosterPrompt,
  extractPosterFields,
  fetchPosterImage,
  isRetryableGeminiError,
  POSTER_IMAGE_MAX_BYTES,
  POSTER_NOTICE_TEXT,
  posterEntriesFromExtraction,
  type PosterExtraction,
  posterFlags,
  type PosterStageDeps,
  posterTargetsMissing,
} from '../format-pending/poster.ts';

// =============================================================================
// 대상 판정
// =============================================================================

Deno.test('posterTargetsMissing: 참가비·장소 둘 다 없으면 true', () => {
  assertEquals(posterTargetsMissing([], null, null), true);
});

Deno.test('posterTargetsMissing: 크롤 컬럼으로 둘 다 확보되면 false', () => {
  assertEquals(posterTargetsMissing([], 30000, '광주시민테니스장'), false);
});

Deno.test('posterTargetsMissing: 정형화 필드로 확보돼도 false', () => {
  const fields = [
    { label: '참가비', value: '팀당 30,000원' },
    { label: '장소', value: '진월국제테니스장' },
  ];
  assertEquals(posterTargetsMissing(fields, null, null), false);
});

Deno.test('posterTargetsMissing: 참가비 라벨이어도 금액이 없으면 미확보로 본다', () => {
  const fields = [{ label: '참가비', value: '추후 공지' }];
  assertEquals(posterTargetsMissing(fields, null, '테니스장'), true);
});

Deno.test('posterTargetsMissing: 장소만 없어도 true (부분 결손 보완)', () => {
  assertEquals(posterTargetsMissing([], 30000, null), true);
});

// =============================================================================
// 추출 결과 → 항목/문서/flag
// =============================================================================

const FULL_EXTRACTION: PosterExtraction = {
  entry_fee: '팀당  60,000원',
  account: '농협 301-1234-5678-90 (예금주 전북협회)',
  venue: '전주 화산테니스장',
  application_period: '2026. 9. 1 ~ 9. 10',
};

Deno.test('posterEntriesFromExtraction: 빈 값은 버리고 라벨에 (포스터) 출처를 새긴다', () => {
  const entries = posterEntriesFromExtraction({
    ...FULL_EXTRACTION,
    account: '',
    application_period: '   ',
  });
  assertEquals(entries, [
    { label: '참가비(포스터)', value: '팀당 60,000원' }, // 공백 정규화 포함
    { label: '장소(포스터)', value: '전주 화산테니스장' },
  ]);
});

Deno.test('appendPosterSection: other 섹션이 없으면 notice+key_values 로 신설한다', () => {
  const doc: RegulationDocument = {
    schema_version: 1,
    sections: [{
      code: 'eligibility',
      availability: 'present',
      blocks: [{ type: 'paragraph', text: '개나리부' }],
    }],
  };
  const entries = posterEntriesFromExtraction(FULL_EXTRACTION);
  const appended = appendPosterSection(doc, entries);
  // 원본 불변
  assertEquals(doc.sections.length, 1);
  const other = appended.sections.find((s) => s.code === 'other');
  assert(other, 'other 섹션이 추가돼야 한다');
  assertEquals(other!.availability, 'present');
  assertEquals(other!.blocks[0], { type: 'notice', text: POSTER_NOTICE_TEXT });
  assertEquals(other!.blocks[1].type, 'key_values');
  assertEquals(other!.blocks[1].entries?.length, 4);
});

Deno.test('appendPosterSection: 기존 other 섹션 뒤에 붙인다 + normalize 왕복 보존', () => {
  const doc: RegulationDocument = {
    schema_version: 1,
    sections: [{
      code: 'other',
      availability: 'present',
      blocks: [{ type: 'paragraph', text: '기존 안내' }],
    }],
  };
  const appended = appendPosterSection(doc, posterEntriesFromExtraction(FULL_EXTRACTION));
  assertEquals(appended.sections.length, 1);
  assertEquals(appended.sections[0].blocks.length, 3);
  assertEquals(appended.sections[0].blocks[0], { type: 'paragraph', text: '기존 안내' });

  // 스테이징 → 승인 경로에서 다시 normalize 되어도 포스터 항목이 살아남는다.
  const normalized = normalizeRegulationDocument(appended as unknown);
  assert(normalized, 'normalize 를 통과해야 한다');
  const entries = normalized!.sections[0].blocks.find((b) => b.type === 'key_values')?.entries;
  assert(entries?.some((e) => e.label === '입금계좌(포스터)'));
});

Deno.test('appendPosterSection: 추출 항목이 없으면 문서를 그대로 반환한다', () => {
  const doc: RegulationDocument = { schema_version: 1, sections: [] };
  assertEquals(appendPosterSection(doc, []), doc);
});

Deno.test('posterFlags: poster_extracted 코드 + 값 마스킹(계좌 원문 비노출)', () => {
  const flags = posterFlags(posterEntriesFromExtraction(FULL_EXTRACTION));
  assertEquals(flags.length, 4);
  const account = flags.find((f) => f.field === '입금계좌(포스터)');
  assert(account, '계좌 flag 존재');
  assertEquals(account!.code, 'poster_extracted');
  assert(!account!.masked.includes('5678'), '계좌 뒷자리는 마스킹');
});

Deno.test('buildPosterPrompt: 생성 금지·불확실은 빈 문자열 지시를 포함한다', () => {
  const p = buildPosterPrompt('제1회 테스트배');
  assert(p.includes('절대 만들지 말 것'));
  assert(p.includes('빈 문자열'));
  assert(p.includes('제1회 테스트배'));
});

// =============================================================================
// 이미지 fetch 검증 (fake fetch 주입)
// =============================================================================

function fakeFetch(body: BodyInit | null, init: ResponseInit): typeof fetch {
  return (() => Promise.resolve(new Response(body, init))) as typeof fetch;
}

Deno.test('fetchPosterImage: 이미지가 아닌 content-type 은 거부', async () => {
  const r = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch('<html></html>', { status: 200, headers: { 'content-type': 'text/html' } }),
  );
  assertEquals(r.ok, false);
});

Deno.test('fetchPosterImage: content-length 상한 초과는 본문을 읽지 않고 거부', async () => {
  const r = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch(new Uint8Array(8), {
      status: 200,
      headers: {
        'content-type': 'image/jpeg',
        'content-length': String(POSTER_IMAGE_MAX_BYTES + 1),
      },
    }),
  );
  assertEquals(r.ok, false);
});

Deno.test('fetchPosterImage: 실제 바이트가 상한을 넘어도 거부', async () => {
  const big = new Uint8Array(POSTER_IMAGE_MAX_BYTES + 1);
  const r = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch(big, { status: 200, headers: { 'content-type': 'image/jpeg' } }),
  );
  assertEquals(r.ok, false);
});

Deno.test('fetchPosterImage: HTTP 오류·빈 본문 거부', async () => {
  const notFound = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch(null, { status: 404 }),
  );
  assertEquals(notFound.ok, false);
  const empty = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch(new Uint8Array(0), { status: 200, headers: { 'content-type': 'image/png' } }),
  );
  assertEquals(empty.ok, false);
});

Deno.test('fetchPosterImage: 정상 이미지는 base64 인코딩 + 비표준 image/jpg 정규화', async () => {
  const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
  const r = await fetchPosterImage(
    'https://x.test/p.jpg',
    fakeFetch(bytes, { status: 200, headers: { 'content-type': 'image/jpg; charset=binary' } }),
  );
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.image.mimeType, 'image/jpeg');
    assertEquals(r.image.data, '/9j/4A==');
  }
});

// =============================================================================
// 오케스트레이션 — 429 재시도·대회당 1회 흐름 (fake deps)
// =============================================================================

function makeDeps(
  generateResults: Array<PosterExtraction | Error>,
): { deps: PosterStageDeps; sleeps: number[]; generateCalls: number[] } {
  const sleeps: number[] = [];
  let call = 0;
  const generateCalls: number[] = [];
  const deps: PosterStageDeps = {
    fetchImage: () =>
      Promise.resolve({ ok: true, image: { mimeType: 'image/jpeg', data: 'QUJD' } }),
    generate: (_prompt: string, _image: InlineImage) => {
      generateCalls.push(++call);
      const next = generateResults.shift();
      if (next instanceof Error) return Promise.reject(next);
      if (!next) return Promise.reject(new Error('no scripted result'));
      return Promise.resolve(next);
    },
    sleep: (ms) => {
      sleeps.push(ms);
      return Promise.resolve();
    },
  };
  return { deps, sleeps, generateCalls };
}

Deno.test('extractPosterFields: 429 는 간격을 두고 재시도 후 성공한다', async () => {
  const { deps, sleeps, generateCalls } = makeDeps([
    new Error('Gemini 429: rate limited'),
    new Error('Gemini 503: overloaded'),
    FULL_EXTRACTION,
  ]);
  const r = await extractPosterFields(deps, '테스트배', 'https://x.test/p.jpg');
  assert(r.ok);
  if (r.ok) assertEquals(r.entries.length, 4);
  assertEquals(generateCalls.length, 3);
  assertEquals(sleeps, [1000, 2000, 8000]); // 첫 호출 간격 + 재시도 백오프
});

Deno.test('extractPosterFields: 재시도 소진 시 실패로 반환(호출측이 1회 시도로 마감)', async () => {
  const { deps, generateCalls } = makeDeps([
    new Error('Gemini 429: a'),
    new Error('Gemini 429: b'),
    new Error('Gemini 429: c'),
  ]);
  const r = await extractPosterFields(deps, '테스트배', 'https://x.test/p.jpg');
  assertEquals(r.ok, false);
  assertEquals(generateCalls.length, 3);
});

Deno.test('extractPosterFields: 비재시도 오류(400 등)는 즉시 실패', async () => {
  const { deps, generateCalls } = makeDeps([new Error('Gemini 400: bad request')]);
  const r = await extractPosterFields(deps, '테스트배', 'https://x.test/p.jpg');
  assertEquals(r.ok, false);
  assertEquals(generateCalls.length, 1);
});

Deno.test('extractPosterFields: 이미지 검증 실패면 Gemini 를 호출하지 않는다', async () => {
  const { deps, generateCalls } = makeDeps([FULL_EXTRACTION]);
  deps.fetchImage = () => Promise.resolve({ ok: false, reason: 'not an image: text/html' });
  const r = await extractPosterFields(deps, '테스트배', 'https://x.test/p.jpg');
  assertEquals(r.ok, false);
  assertEquals(generateCalls.length, 0);
});

Deno.test('isRetryableGeminiError: 429/5xx 만 재시도 대상', () => {
  assertEquals(isRetryableGeminiError('Gemini 429: quota'), true);
  assertEquals(isRetryableGeminiError('Gemini 500: internal'), true);
  assertEquals(isRetryableGeminiError('Gemini 503: overloaded'), true);
  assertEquals(isRetryableGeminiError('Gemini 400: invalid'), false);
  assertEquals(isRetryableGeminiError('network down'), false);
});
