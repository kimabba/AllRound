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

// 문의처/전화 필드는 원문 대조 검증에서 제외.
// 계좌 정규식(\d{2,}-\d{2,}-\d{2,})이 전화번호(010-2409-6100 등)와도 매칭되는데,
// 크롤된 원문 스냅샷에는 사이트 공용 "경기규정문의" 섹션이 자주 빠져 있어
// 실재하는 정상 연락처가 not_in_source로 오탐되는 사례가 다수(운영 확인, 검토 대기 건 100%가 이 케이스).
const CONTACT_LABEL = /문의|연락|전화|담당|사무국|contact|tel/i;

export function verifyAgainstSource(
  result: RegulationResult,
  sourceText: string,
): { ok: boolean; flags: FormatFlag[] } {
  const flags: FormatFlag[] = [];
  if (result.unusual) flags.push({ code: 'unusual', field: '_model', masked: '' });
  if (typeof result.confidence === 'number' && result.confidence < 0.5) {
    flags.push({ code: 'low_confidence', field: '_model', masked: '' });
  }
  // 원문의 개별 숫자 런(구분자 포함)들을 각각 digits-only로. 전체 concat 금지(오탐 방지).
  const runs = [...sourceText.matchAll(/\d[\d,.-]*\d|\d/g)].map((m) => m[0].replace(/[^0-9]/g, ''));
  const seen = new Set<string>();
  // prize도 순위별 상금액을 구체적으로 뽑게 했으므로(buildPrompt) 같은 원문 대조를 거친다.
  // 안 그러면 모델이 지어낸 상금이 검증을 우회해 스테이징된다(금융 할루시 방어 일관성).
  const checked = result.prize
    ? [...result.regulation_fields, { label: '시상', value: result.prize }]
    : result.regulation_fields;
  for (const f of checked) {
    if (CONTACT_LABEL.test(f.label)) continue; // 문의처/전화 필드는 원문 대조 검증 제외(과탐 방지)
    for (const tok of sensitiveTokens(f.value)) {
      const d = digitsOnly(tok);
      if (d.length === 0) continue;
      const key = `${f.label}|${d}`;
      if (seen.has(key)) continue; // 중복 flag 방지(계좌/날짜 정규식 겹침)
      seen.add(key);
      if (!runs.some((r) => r.includes(d))) {
        flags.push({ code: 'not_in_source', field: f.label, masked: maskValue(tok) });
      }
    }
  }
  return { ok: flags.length === 0, flags };
}
