import type { RegulationField } from './regulation.ts';

export const REGULATION_DOCUMENT_VERSION = 1;

export const REGULATION_SECTION_CODES = [
  'eligibility',
  'schedule_venue',
  'registration_payment',
  'match_operations',
  'awards',
  'refund_changes',
  'notices_contact',
  'other',
] as const;

export type RegulationSectionCode = typeof REGULATION_SECTION_CODES[number];
export type RegulationAvailability = 'present' | 'not_announced' | 'not_applicable';
export type RegulationBlockType =
  | 'paragraph'
  | 'subheading'
  | 'bullets'
  | 'key_values'
  | 'table'
  | 'notice'
  | 'division_schedule';

export interface RegulationEntry {
  label: string;
  value: string;
}

export interface RegulationTableRow {
  cells: string[];
}

export interface RegulationDivisionItem {
  name: string;
  date?: string;
  venue?: string;
  fee?: string;
  account?: string;
  capacity?: string;
}

export interface RegulationBlock {
  type: RegulationBlockType;
  text?: string;
  items?: string[];
  entries?: RegulationEntry[];
  columns?: string[];
  rows?: RegulationTableRow[];
  divisions?: RegulationDivisionItem[];
}

export interface RegulationSection {
  code: RegulationSectionCode;
  availability: RegulationAvailability;
  blocks: RegulationBlock[];
}

export interface RegulationDocument {
  schema_version: typeof REGULATION_DOCUMENT_VERSION;
  summary?: string;
  sections: RegulationSection[];
}

const SECTION_LABELS: Record<RegulationSectionCode, string> = {
  eligibility: '참가 부서 및 자격',
  schedule_venue: '일정 및 장소',
  registration_payment: '신청 및 결제',
  match_operations: '경기 방식 및 운영',
  awards: '시상 및 참가상품',
  refund_changes: '변경·취소·환불',
  notices_contact: '유의사항 및 문의',
  other: '기타 안내',
};

const BLOCK_TYPES = new Set<RegulationBlockType>([
  'paragraph',
  'subheading',
  'bullets',
  'key_values',
  'table',
  'notice',
  'division_schedule',
]);
const AVAILABILITIES = new Set<RegulationAvailability>([
  'present',
  'not_announced',
  'not_applicable',
]);
const SECTION_CODE_SET = new Set<RegulationSectionCode>(REGULATION_SECTION_CODES);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function cleanText(value: unknown, max: number): string | undefined {
  if (typeof value !== 'string') return undefined;
  const text = value.replace(/\s+/g, ' ').trim();
  if (!text) return undefined;
  return text.length <= max ? text : text.slice(0, max).trimEnd();
}

function cleanLines(value: unknown, limit: number, max: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => cleanText(item, max))
    .filter((item): item is string => item !== undefined)
    .slice(0, limit);
}

function normalizeEntries(value: unknown): RegulationEntry[] {
  if (!Array.isArray(value)) return [];
  const out: RegulationEntry[] = [];
  for (const item of value.slice(0, 30)) {
    if (!isRecord(item)) continue;
    const label = cleanText(item.label, 80);
    const entryValue = cleanText(item.value, 1000);
    if (label && entryValue) out.push({ label, value: entryValue });
  }
  return out;
}

function normalizeRows(value: unknown): RegulationTableRow[] {
  if (!Array.isArray(value)) return [];
  const out: RegulationTableRow[] = [];
  for (const item of value.slice(0, 50)) {
    if (!isRecord(item)) continue;
    const cells = cleanLines(item.cells, 8, 500);
    if (cells.length > 0) out.push({ cells });
  }
  return out;
}

function normalizeDivisions(value: unknown): RegulationDivisionItem[] {
  if (!Array.isArray(value)) return [];
  const out: RegulationDivisionItem[] = [];
  for (const item of value.slice(0, 30)) {
    if (!isRecord(item)) continue;
    const name = cleanText(item.name, 120);
    if (!name) continue;
    out.push({
      name,
      date: cleanText(item.date, 160),
      venue: cleanText(item.venue, 300),
      fee: cleanText(item.fee, 200),
      account: cleanText(item.account, 300),
      capacity: cleanText(item.capacity, 160),
    });
  }
  return out;
}

function normalizeBlock(value: unknown): RegulationBlock | null {
  if (!isRecord(value) || typeof value.type !== 'string') return null;
  if (!BLOCK_TYPES.has(value.type as RegulationBlockType)) return null;
  const type = value.type as RegulationBlockType;

  switch (type) {
    case 'paragraph':
    case 'notice': {
      const text = cleanText(value.text, 2000);
      return text ? { type, text } : null;
    }
    case 'subheading': {
      const text = cleanText(value.text, 160);
      return text ? { type, text } : null;
    }
    case 'bullets': {
      const items = cleanLines(value.items, 50, 800);
      return items.length > 0 ? { type, items } : null;
    }
    case 'key_values': {
      const entries = normalizeEntries(value.entries);
      return entries.length > 0 ? { type, entries } : null;
    }
    case 'table': {
      const columns = cleanLines(value.columns, 8, 120);
      const rows = normalizeRows(value.rows);
      return rows.length > 0 ? { type, columns, rows } : null;
    }
    case 'division_schedule': {
      const divisions = normalizeDivisions(value.divisions);
      return divisions.length > 0 ? { type, divisions } : null;
    }
  }
}

export function normalizeRegulationDocument(raw: unknown): RegulationDocument | null {
  if (!isRecord(raw) || raw.schema_version !== REGULATION_DOCUMENT_VERSION) return null;
  if (!Array.isArray(raw.sections)) return null;

  const byCode = new Map<RegulationSectionCode, RegulationSection>();
  for (const item of raw.sections) {
    if (!isRecord(item) || typeof item.code !== 'string') continue;
    if (!SECTION_CODE_SET.has(item.code as RegulationSectionCode)) continue;
    const code = item.code as RegulationSectionCode;
    const availability = typeof item.availability === 'string' &&
        AVAILABILITIES.has(item.availability as RegulationAvailability)
      ? item.availability as RegulationAvailability
      : 'present';
    const blocks = Array.isArray(item.blocks)
      ? item.blocks.map(normalizeBlock).filter((block): block is RegulationBlock => block !== null)
        .slice(0, 20)
      : [];
    if (availability === 'present' && blocks.length === 0) continue;

    const existing = byCode.get(code);
    if (existing && existing.availability === 'present' && availability === 'present') {
      existing.blocks.push(...blocks);
      existing.blocks = existing.blocks.slice(0, 20);
    } else if (!existing || availability === 'present') {
      byCode.set(code, { code, availability, blocks });
    }
  }

  const sections = REGULATION_SECTION_CODES
    .map((code) => byCode.get(code))
    .filter((section): section is RegulationSection => section !== undefined);
  if (sections.length === 0) return null;
  return {
    schema_version: REGULATION_DOCUMENT_VERSION,
    summary: cleanText(raw.summary, 500),
    sections,
  };
}

export function regulationSectionLabel(code: RegulationSectionCode): string {
  return SECTION_LABELS[code];
}

function normalizedLegacyLabel(label: string): string {
  return label.toLowerCase().replace(/[\s_\-·:/()]/g, '');
}

export function sectionCodeForLegacyLabel(label: string): RegulationSectionCode {
  const value = normalizedLegacyLabel(label);
  if (/참가부서|참가자격|출전규정|예외부서|시드기준|참가규모|경기종목/.test(value)) {
    return 'eligibility';
  }
  if (/일시|일정|대회일|경기일|장소|경기장|개최지/.test(value)) {
    return 'schedule_venue';
  }
  if (/환불|취소|변경/.test(value)) return 'refund_changes';
  if (/신청|접수|참가비|입금|계좌|결제|예금주/.test(value)) {
    return 'registration_payment';
  }
  if (/시상|상금|참가상품|기념품/.test(value)) return 'awards';
  if (/경기방식|진행방식|운영|사용구|주최|주관|후원|협찬/.test(value)) {
    return 'match_operations';
  }
  if (/문의|연락|전화|담당|안내/.test(value)) return 'notices_contact';
  return 'other';
}

export function regulationDocumentFromLegacy(
  fields: RegulationField[],
  notes: string[] = [],
): RegulationDocument | null {
  const grouped = new Map<RegulationSectionCode, RegulationEntry[]>();
  for (const field of fields) {
    const label = cleanText(field.label, 80);
    const value = cleanText(field.value, 1000);
    if (!label || !value) continue;
    const code = sectionCodeForLegacyLabel(label);
    const entries = grouped.get(code) ?? [];
    entries.push({ label, value });
    grouped.set(code, entries);
  }

  const sections: RegulationSection[] = [];
  for (const code of REGULATION_SECTION_CODES) {
    const entries = grouped.get(code);
    if (entries?.length) {
      sections.push({ code, availability: 'present', blocks: [{ type: 'key_values', entries }] });
    }
  }
  const cleanNotes = notes.map((note) => cleanText(note, 800)).filter((note): note is string =>
    note !== undefined
  );
  if (cleanNotes.length > 0) {
    const existing = sections.find((section) => section.code === 'notices_contact');
    const noticeBlock: RegulationBlock = { type: 'bullets', items: cleanNotes.slice(0, 50) };
    if (existing) existing.blocks.push(noticeBlock);
    else {
      sections.push({ code: 'notices_contact', availability: 'present', blocks: [noticeBlock] });
      sections.sort((a, b) =>
        REGULATION_SECTION_CODES.indexOf(a.code) - REGULATION_SECTION_CODES.indexOf(b.code)
      );
    }
  }
  return sections.length > 0 ? { schema_version: REGULATION_DOCUMENT_VERSION, sections } : null;
}

export function mergeRegulationDocuments(
  preferred: RegulationDocument | null,
  supplement: RegulationDocument,
): RegulationDocument {
  if (!preferred) return supplement;
  const preferredByCode = new Map(preferred.sections.map((section) => [section.code, section]));
  const supplementByCode = new Map(supplement.sections.map((section) => [section.code, section]));
  const sections = REGULATION_SECTION_CODES.map((code) =>
    preferredByCode.get(code) ?? supplementByCode.get(code)
  ).filter((section): section is RegulationSection => section !== undefined);
  return {
    schema_version: REGULATION_DOCUMENT_VERSION,
    summary: supplement.summary ?? preferred.summary,
    sections,
  };
}

export function regulationDocumentToFields(document: RegulationDocument): RegulationField[] {
  const out: RegulationField[] = [];
  for (const section of document.sections) {
    if (section.availability !== 'present') continue;
    for (const block of section.blocks) {
      if (block.type === 'key_values') out.push(...(block.entries ?? []));
      if (block.type === 'division_schedule') {
        const value = (block.divisions ?? []).map((division) =>
          [
            division.name,
            division.date,
            division.venue,
            division.fee,
            division.account,
            division.capacity,
          ]
            .filter((part): part is string => Boolean(part))
            .join(' · ')
        ).join('\n');
        if (value) out.push({ label: '부서별 일정·장소', value });
      }
    }
  }
  return out;
}

export function regulationDocumentToNotes(document: RegulationDocument): string[] {
  const section = document.sections.find((item) => item.code === 'notices_contact');
  if (!section || section.availability !== 'present') return [];
  const out: string[] = [];
  for (const block of section.blocks) {
    if (block.type === 'notice' && block.text) out.push(block.text);
    if (block.type === 'bullets') out.push(...(block.items ?? []));
  }
  return out;
}

function blockLines(block: RegulationBlock): string[] {
  switch (block.type) {
    case 'subheading':
      return block.text ? [`◈ ${block.text}`] : [];
    case 'paragraph':
      return block.text ? [block.text] : [];
    case 'notice':
      return block.text ? [`※ ${block.text}`] : [];
    case 'bullets':
      return (block.items ?? []).map((item) => `- ${item}`);
    case 'table':
      return [
        ...((block.columns ?? []).length > 0 ? [(block.columns ?? []).join(' | ')] : []),
        ...(block.rows ?? []).map((row) => row.cells.join(' | ')),
      ];
    case 'key_values':
    case 'division_schedule':
      return [];
  }
}

export function regulationDocumentToBody(document: RegulationDocument): string {
  const lines: string[] = [];
  for (const section of document.sections) {
    if (section.availability !== 'present') continue;
    const content = section.blocks.flatMap(blockLines);
    if (content.length === 0) continue;
    lines.push(`● ${SECTION_LABELS[section.code]}`, ...content);
  }
  return lines.join('\n').trim();
}

export function regulationDocumentVerificationFields(
  document: RegulationDocument,
): RegulationField[] {
  const out: RegulationField[] = [];
  for (const section of document.sections) {
    if (section.availability !== 'present') continue;
    // 문의처 label만 전화번호 오탐 예외를 적용한다. notices_contact 전체를
    // "문의"로 넘기면 그 섹션의 금액·날짜까지 원문 검증을 우회할 수 있다.
    const sectionLabel = section.code === 'notices_contact'
      ? '유의사항'
      : SECTION_LABELS[section.code];
    for (const block of section.blocks) {
      if (block.text) out.push({ label: sectionLabel, value: block.text });
      for (const item of block.items ?? []) out.push({ label: sectionLabel, value: item });
      out.push(...(block.entries ?? []));
      for (const row of block.rows ?? []) {
        out.push({ label: sectionLabel, value: row.cells.join(' ') });
      }
      for (const division of block.divisions ?? []) {
        out.push({
          label: sectionLabel,
          value: [
            division.name,
            division.date,
            division.venue,
            division.fee,
            division.account,
            division.capacity,
          ].filter((part): part is string => Boolean(part)).join(' '),
        });
      }
    }
  }
  return out;
}

export function regulationDocumentText(document: RegulationDocument): string {
  const lines: string[] = [];
  if (document.summary) lines.push(document.summary);
  for (const section of document.sections) {
    if (section.availability !== 'present') continue;
    lines.push(SECTION_LABELS[section.code]);
    for (const block of section.blocks) {
      if (block.text) lines.push(block.text);
      lines.push(...(block.items ?? []));
      for (const entry of block.entries ?? []) lines.push(`${entry.label}: ${entry.value}`);
      if ((block.columns ?? []).length > 0) lines.push((block.columns ?? []).join(' | '));
      for (const row of block.rows ?? []) lines.push(row.cells.join(' | '));
      for (const division of block.divisions ?? []) {
        lines.push(
          [
            division.name,
            division.date,
            division.venue,
            division.fee,
            division.account,
            division.capacity,
          ].filter((part): part is string => Boolean(part)).join(' · '),
        );
      }
    }
  }
  return lines.join('\n');
}
