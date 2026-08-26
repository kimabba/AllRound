// format-pending/poster.ts
//
// 포스터 이미지 보완 단계 (P6): 원문 텍스트에 없고 포스터 이미지 안에만 있는
// 참가비·입금계좌·장소·신청기간을 Gemini vision 으로 추출한다.
//
// 안전 원칙:
//   - 이미지 텍스트는 원문 대조(verifyAgainstSource)가 **불가능**하다. 그래서 이
//     단계의 결과는 무조건 format_staged → needs_review 검수함 경유로만 반영한다.
//     AI 출력이 검수 없이 published 필드에 직접 쓰이는 경로를 만들지 않는다.
//   - 출처 표기: 항목 라벨에 '(포스터)' 접미, 문서에 notice 블록, format_flags 에
//     code='poster_extracted' 를 남겨 검수 화면에서 출처가 보이게 한다.
//   - 대회당 1회 호출: 시도 자체를 tournaments.poster_vision_at 에 기록해(호출측)
//     재큐돼도 재호출하지 않는다. 429/일시 오류만 이 안에서 재시도한다.
//
// CI Deno 잡은 --allow-net 이 없다 — fetch/Gemini/sleep 을 주입 seam 으로 분리해
// 인메모리 fake 로 검증한다(deno-fake-seam 패턴).

import { encodeBase64 } from 'std/encoding/base64.ts';
import type { InlineImage } from '../_shared/gemini.ts';
import type { RegulationField } from '../_shared/regulation.ts';
import {
  REGULATION_DOCUMENT_VERSION,
  type RegulationDocument,
  type RegulationEntry,
} from '../_shared/regulation_document.ts';
import { type FormatFlag, maskValue } from './logic.ts';

export const POSTER_IMAGE_MAX_BYTES = 4 * 1024 * 1024;

// content-type → Gemini mimeType 정규화(image/jpg 같은 비표준 표기 흡수).
const ALLOWED_IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': 'image/jpeg',
  'image/jpg': 'image/jpeg',
  'image/png': 'image/png',
  'image/webp': 'image/webp',
  'image/gif': 'image/gif',
};

export interface PosterExtraction {
  entry_fee: string;
  account: string;
  venue: string;
  application_period: string;
}

export const POSTER_RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    entry_fee: { type: 'string' },
    account: { type: 'string' },
    venue: { type: 'string' },
    application_period: { type: 'string' },
  },
  required: ['entry_fee', 'account', 'venue', 'application_period'],
};

export function buildPosterPrompt(title: string): string {
  return [
    '다음 이미지는 동호인 테니스/풋살 대회 포스터(요강 이미지)다.',
    '이미지에 실제로 적혀 있는 정보만 추출하라.',
    '규칙: 이미지에 없는 정보를 절대 만들지 말 것. 글자가 흐릿하거나 불확실하면 빈 문자열("")로 남길 것.',
    '- entry_fee: 참가비. 이미지 원문 표기 그대로(예: "팀당 60,000원").',
    '- account: 입금계좌. 은행명·계좌번호·예금주를 이미지 원문 그대로.',
    '- venue: 대회 장소(경기장명).',
    '- application_period: 신청(접수) 기간.',
    `대회명: ${title}`,
  ].join('\n');
}

const FEE_LABEL = /참가비|회비|참가료/;
const FEE_VALUE = /[0-9][0-9,]*\s*원/;
const VENUE_LABEL = /장소|경기장|구장|코트/;

/**
 * 포스터 보완 대상 판정: 원문 텍스트(정형화 결과 fields + 크롤 컬럼)에서
 * 참가비·장소 중 하나라도 확보되지 않았으면 true.
 */
export function posterTargetsMissing(
  fields: RegulationField[],
  entryFee: number | null,
  location: string | null,
): boolean {
  const feeKnown = entryFee !== null ||
    fields.some((f) => FEE_LABEL.test(f.label) && FEE_VALUE.test(f.value));
  const venueKnown = Boolean(location) || fields.some((f) => VENUE_LABEL.test(f.label));
  return !feeKnown || !venueKnown;
}

const POSTER_ENTRY_LABELS: Array<[keyof PosterExtraction, string]> = [
  ['entry_fee', '참가비(포스터)'],
  ['account', '입금계좌(포스터)'],
  ['venue', '장소(포스터)'],
  ['application_period', '신청기간(포스터)'],
];

/** 모델 응답 → 라벨 항목. 빈 값은 버리고 라벨에 출처('(포스터)')를 새긴다. */
export function posterEntriesFromExtraction(extraction: PosterExtraction): RegulationEntry[] {
  const out: RegulationEntry[] = [];
  for (const [key, label] of POSTER_ENTRY_LABELS) {
    const raw = extraction[key];
    const value = typeof raw === 'string' ? raw.replace(/\s+/g, ' ').trim() : '';
    if (value) out.push({ label, value });
  }
  return out;
}

export const POSTER_NOTICE_TEXT =
  '아래 항목은 포스터 이미지에서 AI가 추출한 값입니다(원문 대조 불가 — 검수 후 승인 필요).';

/**
 * 포스터 추출 항목을 문서의 other 섹션 끝에 붙인다. 원문 기반 섹션과 섞지 않고
 * notice + key_values 블록으로 출처를 명시한다. 원본 문서는 변경하지 않는다.
 */
export function appendPosterSection(
  document: RegulationDocument,
  entries: RegulationEntry[],
): RegulationDocument {
  if (entries.length === 0) return document;
  const posterBlocks = [
    { type: 'notice' as const, text: POSTER_NOTICE_TEXT },
    { type: 'key_values' as const, entries },
  ];
  const sections = document.sections.map((section) =>
    section.code === 'other'
      ? {
        ...section,
        availability: 'present' as const,
        blocks: [...section.blocks, ...posterBlocks],
      }
      : section
  );
  if (!sections.some((section) => section.code === 'other')) {
    sections.push({ code: 'other', availability: 'present', blocks: posterBlocks });
  }
  return { ...document, schema_version: REGULATION_DOCUMENT_VERSION, sections };
}

/** 검수함 노출용 flag — 값은 마스킹해 flag 로 원문이 새지 않게 한다. */
export function posterFlags(entries: RegulationEntry[]): FormatFlag[] {
  return entries.map((entry) => ({
    code: 'poster_extracted',
    field: entry.label,
    masked: maskValue(entry.value),
  }));
}

export type PosterImageResult =
  | { ok: true; image: InlineImage }
  | { ok: false; reason: string };

/** 포스터 이미지 fetch + 검증(content-type·크기 상한) + base64 인코딩. */
export async function fetchPosterImage(
  url: string,
  fetchFn: typeof fetch = fetch,
): Promise<PosterImageResult> {
  let res: Response;
  try {
    res = await fetchFn(url, {
      headers: { 'User-Agent': 'MatchUpBot/1.0 (+https://matchup.app)' },
    });
  } catch (e) {
    return { ok: false, reason: `fetch failed: ${(e as Error).message}` };
  }
  if (!res.ok) return { ok: false, reason: `fetch failed ${res.status}` };
  const contentType = (res.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
  const mimeType = ALLOWED_IMAGE_TYPES[contentType];
  if (!mimeType) return { ok: false, reason: `not an image: ${contentType || 'unknown'}` };
  const declared = Number(res.headers.get('content-length') ?? '0');
  if (declared > POSTER_IMAGE_MAX_BYTES) return { ok: false, reason: `too large: ${declared}B` };
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.byteLength > POSTER_IMAGE_MAX_BYTES) {
    return { ok: false, reason: `too large: ${bytes.byteLength}B` };
  }
  if (bytes.byteLength === 0) return { ok: false, reason: 'empty image' };
  return { ok: true, image: { mimeType, data: encodeBase64(bytes) } };
}

/** 무료 티어 분당 한도(비공개) 대비 — 텍스트 정형화 호출과의 최소 간격. */
export const POSTER_CALL_SPACING_MS = 1000;
const RETRY_DELAYS_MS = [2000, 8000];

// generateStructured 계열은 실패 시 `Gemini ${status}: ...` 로 던진다.
// 429(rate limit)·5xx 만 재시도 대상.
export function isRetryableGeminiError(message: string): boolean {
  return /Gemini (429|5\d\d)\b/.test(message);
}

export interface PosterStageDeps {
  fetchImage: (url: string) => Promise<PosterImageResult>;
  generate: (prompt: string, image: InlineImage) => Promise<PosterExtraction>;
  sleep: (ms: number) => Promise<void>;
}

export type PosterExtractResult =
  | { ok: true; entries: RegulationEntry[] }
  | { ok: false; reason: string };

/**
 * 포스터 1장 → 추출 항목. Gemini 호출은 429/5xx 에 한해 최대 2회 재시도하고,
 * 매 시도 전 간격을 둔다. 이미지 검증 실패·비재시도 오류는 즉시 실패로 반환한다
 * (호출측이 poster_vision_at 를 찍어 대회당 1회로 마감한다).
 */
export async function extractPosterFields(
  deps: PosterStageDeps,
  title: string,
  posterUrl: string,
): Promise<PosterExtractResult> {
  const fetched = await deps.fetchImage(posterUrl);
  if (!fetched.ok) return { ok: false, reason: fetched.reason };
  const prompt = buildPosterPrompt(title);
  let lastError = 'poster extraction failed';
  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    await deps.sleep(attempt === 0 ? POSTER_CALL_SPACING_MS : RETRY_DELAYS_MS[attempt - 1]);
    try {
      const extraction = await deps.generate(prompt, fetched.image);
      return { ok: true, entries: posterEntriesFromExtraction(extraction) };
    } catch (e) {
      lastError = (e as Error).message;
      if (!isRetryableGeminiError(lastError)) break;
    }
  }
  return { ok: false, reason: lastError };
}
