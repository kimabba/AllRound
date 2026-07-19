// KATO 상세 공고의 결정적(deterministic) 요강 파서.
//
// 금액·계좌·날짜·장소처럼 틀리면 안 되는 값은 생성형 AI에 맡기지 않고
// 원본 표에서 그대로 추출한다. format-pending은 이 결과를 최종 fields/notes의
// source of truth로 사용하고, AI는 description/body 요약만 담당한다.

import { DOMParser } from 'deno-dom';
import type { RegulationField } from '../../regulation.ts';

type DomNode = {
  nodeName?: string;
  textContent: string;
  childNodes?: ArrayLike<DomNode> & Iterable<DomNode>;
};

type El = DomNode & {
  getAttribute(name: string): string | null;
  querySelector(sel: string): El | null;
  querySelectorAll(sel: string): ArrayLike<El> & Iterable<El>;
};

export interface KatoDivisionSchedule {
  division: string;
  date: string;
  venue?: string;
}

export interface KatoRegulationCoverage {
  expectedDivisionCount: number;
  parsedDivisionCount: number;
  accountCount: number;
  missingSections: string[];
}

export interface KatoRegulationResult {
  fields: RegulationField[];
  notes: string[];
  schedules: KatoDivisionSchedule[];
  location?: string;
  prize?: string;
  coverage: KatoRegulationCoverage;
}

function normalizeLine(value: string): string {
  return value.replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim();
}

function normalizeLabel(value: string): string {
  return value.replace(/\s+/g, '').trim();
}

function collectNodeText(node: DomNode): string {
  const name = (node.nodeName ?? '').toUpperCase();
  if (name === 'BR') return '\n';

  const children = node.childNodes ? Array.from(node.childNodes) : [];
  if (children.length === 0) return node.textContent ?? '';

  const value = children.map(collectNodeText).join('');
  return /^(P|DIV|LI)$/.test(name) ? `${value}\n` : value;
}

function elementLines(element: El): string[] {
  return collectNodeText(element)
    .split(/\n+/)
    .map(normalizeLine)
    .filter((line) => line.length > 0);
}

function elementText(element: El): string {
  return elementLines(element).join('\n');
}

function rowCells(row: El): El[] {
  return Array.from(row.querySelectorAll('td'));
}

function meaningful(value: string | undefined): value is string {
  if (!value) return false;
  return !/^[.·\-\s]+$/.test(value);
}

function unique(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const value of values) {
    const normalized = normalizeLine(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function parseMainTable(root: El): {
  schedules: KatoDivisionSchedule[];
  values: Map<string, string>;
} {
  const table = root.querySelector('#tab1 table.table-bordered') ??
    root.querySelector('#tab1 table');
  if (!table) return { schedules: [], values: new Map() };

  const schedules: KatoDivisionSchedule[] = [];
  const values = new Map<string, string>();
  let remainingScheduleRows = 0;

  for (const row of table.querySelectorAll('tr')) {
    const cells = rowCells(row);
    if (cells.length === 0) continue;

    if (remainingScheduleRows > 0) {
      if (cells.length >= 2) {
        const division = normalizeLine(cells[0].textContent ?? '');
        const date = normalizeLine(cells[1].textContent ?? '');
        if (division && date) schedules.push({ division, date });
      }
      remainingScheduleRows--;
      continue;
    }

    const label = normalizeLabel(cells[0].textContent ?? '');
    if (label === '일시' && cells.length >= 3) {
      const division = normalizeLine(cells[1].textContent ?? '');
      const date = normalizeLine(cells[2].textContent ?? '');
      if (division && date) schedules.push({ division, date });
      const rowSpan = Number(cells[0].getAttribute('rowspan') ?? '1');
      remainingScheduleRows = Number.isInteger(rowSpan) && rowSpan > 1 ? rowSpan - 1 : 0;
      continue;
    }

    if (cells.length < 2 || !label) continue;
    const value = elementText(cells[1]);
    if (meaningful(value)) values.set(label, value);
  }

  return { schedules, values };
}

function parseApplicationSchedules(root: El): KatoDivisionSchedule[] {
  const tab = root.querySelector('#tab2');
  if (!tab) return [];

  const schedules: KatoDivisionSchedule[] = [];
  for (const row of tab.querySelectorAll('tr')) {
    const cells = rowCells(row);
    if (cells.length < 2) continue;

    const division = normalizeLine(cells[0].textContent ?? '');
    const venue = normalizeLine(cells[1].querySelector('.place')?.textContent ?? '');
    const dateBlocks = Array.from(cells[1].querySelectorAll('div'))
      .filter((div) => !((div.getAttribute('class') ?? '').split(/\s+/).includes('place')))
      .map((div) => normalizeLine(div.textContent ?? ''))
      .filter((value) => value.length > 0);
    const date = dateBlocks[0] ?? normalizeLine(
      (cells[1].textContent ?? '').replace(venue, ''),
    );

    if (!division || !date) continue;
    schedules.push({ division, date, venue: venue || undefined });
  }
  return schedules;
}

function mergeSchedules(
  mainSchedules: KatoDivisionSchedule[],
  applicationSchedules: KatoDivisionSchedule[],
): KatoDivisionSchedule[] {
  if (mainSchedules.length === 0) return applicationSchedules;

  const byDivision = new Map(
    applicationSchedules.map((schedule) => [normalizeLabel(schedule.division), schedule]),
  );
  return mainSchedules.map((schedule) => {
    const application = byDivision.get(normalizeLabel(schedule.division));
    if (!application) return schedule;
    return {
      division: schedule.division,
      date: application.date || schedule.date,
      venue: application.venue,
    };
  });
}

const BANK_NAME = /농협|은행|신협|수협|우체국|새마을|카카오|토스|국민|기업|신한|우리|하나/;
const ACCOUNT_NUMBER = /\d{2,}-\d{2,}-\d{2,}/;

function splitApplicationInfo(value: string | undefined): {
  application: string[];
  accounts: string[];
  notes: string[];
} {
  if (!value) return { application: [], accounts: [], notes: [] };

  const lines = value.split('\n').map(normalizeLine).filter(Boolean);
  const application: string[] = [];
  const accounts: string[] = [];
  const notes: string[] = [];
  let note = '';

  const flushNote = () => {
    if (note) notes.push(note);
    note = '';
  };

  for (const line of lines) {
    if (/^[*※]/.test(line)) {
      flushNote();
      note = line.replace(/^[*※]\s*/, '').trim();
      continue;
    }
    if (/부서별\s*입금계좌/.test(line)) {
      flushNote();
      continue;
    }
    if (BANK_NAME.test(line) && ACCOUNT_NUMBER.test(line)) {
      flushNote();
      accounts.push(line.replace(/^[◑●]\s*/, '').trim());
      continue;
    }
    if (note) {
      note = `${note} ${line}`.trim();
      continue;
    }
    application.push(line);
  }
  flushNote();

  return {
    application: unique(application),
    accounts: unique(accounts),
    notes: unique(notes),
  };
}

function addField(fields: RegulationField[], label: string, value: string | undefined): void {
  if (meaningful(value)) fields.push({ label, value });
}

function locationSummary(schedules: KatoDivisionSchedule[]): string | undefined {
  const venues = unique(schedules.map((schedule) => schedule.venue ?? '').filter(Boolean));
  if (venues.length === 0) return undefined;
  if (venues.length === 1) return venues[0];
  return `${venues[0]} 외 ${venues.length - 1}곳`;
}

export function isKatoSource(source: string): boolean {
  return /(^|[-_])kato($|[-_])/.test(source.trim().toLowerCase());
}

export function parseKatoRegulation(html: string): KatoRegulationResult | null {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;
  const root = dom as unknown as El;

  const main = parseMainTable(root);
  const applicationSchedules = parseApplicationSchedules(root);
  const schedules = mergeSchedules(main.schedules, applicationSchedules);
  const accountInfo = splitApplicationInfo(main.values.get('신청안내및입금계좌'));
  const fields: RegulationField[] = [];

  if (schedules.length > 0) {
    addField(
      fields,
      '부서별 일정·장소',
      schedules.map((schedule) =>
        [schedule.division, schedule.date, schedule.venue].filter(Boolean).join(' · ')
      ).join('\n'),
    );
  }

  const directFields: Array<[string, string, string | undefined]> = [
    ['대회안내', '대회 안내', main.values.get('대회안내')],
    ['장소', '장소 안내', main.values.get('장소')],
    ['주최', '주최', main.values.get('주최')],
    ['주관', '주관', main.values.get('주관')],
    ['후원', '후원', main.values.get('후원')],
    ['협찬', '협찬', main.values.get('협찬')],
    ['사용구', '사용구', main.values.get('사용구')],
    ['환불마감', '접수·환불', main.values.get('환불마감')],
  ];
  for (const [, label, value] of directFields) addField(fields, label, value);

  addField(fields, '신청 안내', accountInfo.application.join('\n'));
  addField(fields, '입금계좌', accountInfo.accounts.join('\n'));
  addField(fields, '참가비', main.values.get('참가비'));
  addField(fields, '참가상품', main.values.get('참가상품'));
  addField(fields, '시상', main.values.get('시상'));
  addField(fields, '문의처', main.values.get('감독관및문의처'));
  addField(fields, '시드 기준', main.values.get('시드기준'));
  addField(fields, '출전 규정', main.values.get('출전규정'));
  addField(fields, '예외부서 규정', main.values.get('예외부서규정'));

  const notes = [...accountInfo.notes];
  const prize = main.values.get('시상');
  const prizeAdjustment = prize?.split('\n')
    .map(normalizeLine)
    .find((line) => /팀\s*미만|시상금.*조정/.test(line));
  if (prizeAdjustment) notes.push(prizeAdjustment.replace(/^[*※]\s*/, '').trim());

  const expectedDivisionCount = main.schedules.length || applicationSchedules.length;
  const parsedDivisionCount = schedules.filter((schedule) => Boolean(schedule.venue)).length;
  const missingSections: string[] = [];
  if (expectedDivisionCount === 0) missingSections.push('부서별 일정');
  if (expectedDivisionCount > 0 && parsedDivisionCount !== expectedDivisionCount) {
    missingSections.push('부서별 장소');
  }
  if (accountInfo.accounts.length === 0) missingSections.push('입금계좌');
  if (!meaningful(main.values.get('참가비'))) missingSections.push('참가비');
  if (!meaningful(main.values.get('환불마감'))) missingSections.push('접수·환불');
  if (!meaningful(prize)) missingSections.push('시상');

  return {
    fields,
    notes: unique(notes),
    schedules,
    location: locationSummary(schedules),
    prize,
    coverage: {
      expectedDivisionCount,
      parsedDivisionCount,
      accountCount: accountInfo.accounts.length,
      missingSections,
    },
  };
}
