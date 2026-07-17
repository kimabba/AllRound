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
