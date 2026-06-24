/**
 * 대회 요강(regulation) 정형화 헬퍼.
 *
 * migration 073/074/077 에서 도입된 tournaments.regulation_fields(jsonb)/
 * regulation_body(text) 를 임베딩 텍스트(embed-pending)와 RAG 컨텍스트(chat)
 * 양쪽에서 일관되게 직렬화하기 위한 순수 함수 모음.
 *
 * - regulation_fields: 라벨:값 쌍의 순서 보존 배열. crawler 가 표 순서대로 저장.
 * - regulation_body: 요강 전체 본문. DB(077)에서 이미 ≤2500자로 절단되어 옴.
 *
 * 외부(DB) 데이터는 jsonb 라서 unknown 으로 들어온다. narrowing 후 사용.
 */

/** regulation_fields 한 항목. crawler.ts 의 저장 형태와 동일. */
export interface RegulationField {
  label: string;
  value: string;
}

/**
 * unknown(jsonb) → RegulationField[] 로 안전하게 narrow.
 * label/value 가 모두 비어있지 않은 문자열인 항목만 통과시킨다.
 * 배열이 아니거나 항목 형태가 어긋나면 빈 배열.
 */
export function normalizeRegulationFields(raw: unknown): RegulationField[] {
  if (!Array.isArray(raw)) return [];
  const out: RegulationField[] = [];
  for (const item of raw) {
    if (item === null || typeof item !== 'object') continue;
    const rec = item as Record<string, unknown>;
    const label = rec.label;
    const value = rec.value;
    if (typeof label !== 'string' || typeof value !== 'string') continue;
    const l = label.trim();
    const v = value.trim();
    if (l.length === 0 || v.length === 0) continue;
    out.push({ label: l, value: v });
  }
  return out;
}

/**
 * regulation_fields 를 "라벨: 값 / 라벨: 값" 한 줄 요약으로.
 * 빈 배열이면 빈 문자열.
 */
export function formatRegulationFields(fields: RegulationField[]): string {
  return fields.map((f) => `${f.label}: ${f.value}`).join(' / ');
}

/**
 * 요강 본문을 maxLen 자로 절단 (초과 시 … 부착).
 * null/공백이면 빈 문자열.
 */
export function capRegulationBody(body: string | null | undefined, maxLen: number): string {
  if (!body) return '';
  const trimmed = body.trim();
  if (trimmed.length === 0) return '';
  if (trimmed.length <= maxLen) return trimmed;
  return trimmed.slice(0, maxLen) + '…';
}

/**
 * 임베딩용 요강 텍스트 조각 생성.
 * regulation_fields 요약 + 본문(cap)을 합쳐 반환. 둘 다 없으면 빈 문자열.
 *
 * 임베딩 입력 전체가 과도하게 길어지지 않도록 본문은 fieldsBodyCap 으로 제한.
 */
export function regulationEmbeddingText(
  fields: RegulationField[],
  body: string | null | undefined,
  bodyCap = 1500,
): string {
  const parts: string[] = [];
  const fieldText = formatRegulationFields(fields);
  if (fieldText) parts.push(fieldText);
  const bodyText = capRegulationBody(body, bodyCap);
  if (bodyText) parts.push(bodyText);
  return parts.join('\n');
}

/**
 * RAG 컨텍스트(LLM)용 요강 요약 라인들 생성.
 * - fields → "요강: 장소: …, 주최: …" 한 줄 (있을 때)
 * - body  → 절단 본문 (있을 때, DB에서 이미 ≤2500자지만 컨텍스트 토큰 관리 위해 추가 cap)
 *
 * 들여쓰기는 호출부 컨텍스트 포맷에 맞춰 prefix 로 받는다.
 * 반환은 줄 배열. 비어있으면 빈 배열.
 */
export function buildRegulationContextLines(
  fields: RegulationField[],
  body: string | null | undefined,
  opts: { bodyCap?: number; prefix?: string } = {},
): string[] {
  const bodyCap = opts.bodyCap ?? 1200;
  const prefix = opts.prefix ?? '  ';
  const lines: string[] = [];

  const fieldText = formatRegulationFields(fields);
  if (fieldText) lines.push(`${prefix}요강: ${fieldText}`);

  const bodyText = capRegulationBody(body, bodyCap);
  if (bodyText) {
    // 본문 내 개행은 컨텍스트 가독성 위해 공백 1개로 평탄화.
    const flat = bodyText.replace(/\s*\n\s*/g, ' ');
    lines.push(`${prefix}요강 본문: ${flat}`);
  }

  return lines;
}
