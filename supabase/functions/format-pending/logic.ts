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

export function buildRegulationPrompt(title: string, sourceText: string): string {
  return [
    '다음은 동호인 테니스/풋살 대회 공고 원문이다. 요강을 고정 문서 구조로 정리하라.',
    '규칙: 원문에 없는 정보(금액·계좌·날짜 등)를 절대 만들지 말 것. 불명확하면 생략.',
    '값을 지어냈거나 형식이 처음 보는 구조면 unusual=true. 확신도는 confidence(0~1).',
    'regulation_document.schema_version은 반드시 1이다.',
    '섹션 code와 순서는 eligibility, schedule_venue, registration_payment, match_operations,',
    'awards, refund_changes, notices_contact, other만 사용한다. 같은 code를 중복 생성하지 않는다.',
    '원문에 내용이 있으면 availability=present, 추후 공지는 not_announced, 해당 없음은 not_applicable.',
    'blocks는 paragraph/subheading/bullets/key_values/table/notice/division_schedule만 사용한다.',
    '대제목은 만들지 말고 section code로만 구분한다. 원문 소제목은 subheading에 넣는다.',
    'eligibility의 등급·부서별 참가 자격은 paragraph로 합치지 말고 table로 만든다.',
    '자격 표의 columns는 원문에 맞춰 부서/등급, 출전 기준, 연령, 파트너 조건 등 비교 가능한 열을 사용한다.',
    '한 부서의 공통 자격만 있으면 key_values를 쓰되 기준 이름과 내용을 분리한다.',
    '입금계좌가 원문에 있으면 key_values 또는 division_schedule에 은행명·계좌번호·예금주를 포함한다.',
    '부서마다 일정·장소·참가비·계좌가 다르면 division_schedule 배열에서 부서별로 분리한다.',
    '표는 columns와 rows[{cells}]로 보존하고, 일반 설명은 paragraph, 열거는 bullets로 정리한다.',
    'prize/시상은 순위·부서별 상금액을 원문 그대로 구체적으로(예: 우승 30만원, 준우승 15만원). 뭉뚱그리지 말 것.',
    'format은 경기방식 요약, description은 1~2줄 요약.',
    `대회명: ${title}`,
    '원문:',
    sourceText,
  ].join('\n');
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
// 대회 임원 직책 라벨(사무장/총무/재무/경기이사/감독관 등)도 같은 사유로 전화번호가 오탐되어
// 함께 제외한다(광주오픈 0f5c291d 실증 — #f43e679 후속).
const CONTACT_LABEL =
  /문의|연락|전화|담당|사무국|contact|tel|이사|총무|재무|사무장|감독관|회장|본부석|안내/i;
// CONTACT_LABEL이 '안내'처럼 넓은 단어를 포함해 라벨만으로는 과잉 매칭될 수 있으므로
// (예: "입금계좌 안내", "납부 안내"), 계좌류 키워드가 라벨이나 값에 함께 있으면
// 문의처 필드로 취급하지 않는다. 전화번호 모양 계좌(휴대폰 평생계좌 등)도 있어
// 값 형태 가드만으로는 부족하다. 계좌 검증이 항상 우선한다(검증 완화 금지 결정, 7월).
const ACCOUNT_HINT = /계좌|통장|입금|납부|송금|예금주|이체/;

// 위 라벨 확장이 실제 계좌·금액 값을 가리는 일이 없도록, 라벨이 매칭돼도 값 토큰이
// 전화번호일 때만 대조를 제외한다. 판정은 두 겹:
// 1) 표기 형태 — 0으로 시작하고 구분자는 하이픈/공백/점만(또는 무구분). 쉼표·'원' 등
//    비전화 표기는 배제한다. digitsOnly만 보면 '010,000,000원' 같은 0-prefix 조작 금액이
//    전화로 위장해 원문 대조를 우회한다(금액 검증 우회 방지 — Codex 교차 리뷰).
// 2) 자릿수 — 0으로 시작하는 9~11자리. 국내 계좌번호는 보통 0으로 시작하지 않아
//    (예: 1107-021-677837, 302-1234-5678) 구분된다.
function isPhoneToken(token: string): boolean {
  if (!/^0[\d\-. ]*\d$/.test(token)) return false;
  return /^0\d{8,10}$/.test(token.replace(/[^0-9]/g, ''));
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
  // 원문의 개별 숫자 런(구분자 포함)들을 각각 digits-only로. 전체 concat 금지(오탐 방지).
  const runs = [...sourceText.matchAll(/\d[\d,.-]*\d|\d/g)].map((m) => m[0].replace(/[^0-9]/g, ''));
  const seen = new Set<string>();
  // prize도 순위별 상금액을 구체적으로 뽑게 했으므로(buildPrompt) 같은 원문 대조를 거친다.
  // 안 그러면 모델이 지어낸 상금이 검증을 우회해 스테이징된다(금융 할루시 방어 일관성).
  const checked = result.prize
    ? [...result.regulation_fields, { label: '시상', value: result.prize }]
    : result.regulation_fields;
  for (const f of checked) {
    // 문의처/전화/임원 직책 라벨이면서 계좌류 키워드가 라벨·값 어디에도 없을 때만 대조 제외 후보.
    // (예: label "총무", value "기업은행 계좌 010-…" 같은 전화 모양 계좌를 가리지 않기 위함)
    const isContactField = CONTACT_LABEL.test(f.label) &&
      !ACCOUNT_HINT.test(f.label) && !ACCOUNT_HINT.test(f.value);
    for (const tok of sensitiveTokens(f.value)) {
      const d = digitsOnly(tok);
      if (d.length === 0) continue;
      // 문의처류 라벨이라도 토큰이 전화번호 표기·자릿수일 때만 제외(계좌·금액 검증 완화 금지).
      if (isContactField && isPhoneToken(tok)) continue;
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

// Gemini 는 response_schema 의 enum 값을 문자열로만 받는다. 숫자를 넣으면 호출 자체가
// 400 INVALID_ARGUMENT 로 거부된다("Invalid value at ...enum[0] (TYPE_STRING), 1").
// schema_version 은 프롬프트가 "반드시 1" 이라고 지시하고 required 에도 들어 있으므로
// enum 없이 type 만으로 충분하다. 값 검증은 normalizeRegulationDocument 가 한 번 더 한다.
export const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    regulation_document: {
      type: 'object',
      properties: {
        schema_version: { type: 'integer' },
        summary: { type: 'string' },
        sections: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              code: {
                type: 'string',
                enum: [
                  'eligibility',
                  'schedule_venue',
                  'registration_payment',
                  'match_operations',
                  'awards',
                  'refund_changes',
                  'notices_contact',
                  'other',
                ],
              },
              availability: {
                type: 'string',
                enum: ['present', 'not_announced', 'not_applicable'],
              },
              blocks: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    type: {
                      type: 'string',
                      enum: [
                        'paragraph',
                        'subheading',
                        'bullets',
                        'key_values',
                        'table',
                        'notice',
                        'division_schedule',
                      ],
                    },
                    text: { type: 'string' },
                    items: { type: 'array', items: { type: 'string' } },
                    entries: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: { label: { type: 'string' }, value: { type: 'string' } },
                        required: ['label', 'value'],
                      },
                    },
                    columns: { type: 'array', items: { type: 'string' } },
                    rows: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          cells: { type: 'array', items: { type: 'string' } },
                        },
                        required: ['cells'],
                      },
                    },
                    divisions: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          name: { type: 'string' },
                          date: { type: 'string' },
                          venue: { type: 'string' },
                          fee: { type: 'string' },
                          account: { type: 'string' },
                          capacity: { type: 'string' },
                        },
                        required: ['name'],
                      },
                    },
                  },
                  required: ['type'],
                },
              },
            },
            required: ['code', 'availability', 'blocks'],
          },
        },
      },
      required: ['schema_version', 'sections'],
    },
    prize: { type: 'string' },
    format: { type: 'string' },
    description: { type: 'string' },
    confidence: { type: 'number' },
    unusual: { type: 'boolean' },
  },
  required: [
    'regulation_document',
    'prize',
    'format',
    'description',
    'confidence',
    'unusual',
  ],
};
