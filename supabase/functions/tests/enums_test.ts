import { assertEquals } from 'std/assert/mod.ts';
import {
  canEnter,
  ENTRY_FEE_UNITS,
  FUTSAL_GRADES,
  getDivisionLabel,
  getDivisionsForOrg,
  isValidGrade,
  isValidPlayerOrigin,
  parseDivisionCodes,
  parseRecruiting,
  rankOf,
  REGION_CODES,
  regionCodeFromLabel,
  TENNIS_GRADES,
  TENNIS_ORGS,
} from '../_shared/enums.ts';

Deno.test('shared enums expose stable sport grade order', () => {
  assertEquals(TENNIS_GRADES, ['under1y', 'y1to3', 'y3to5', 'over5y']);
  assertEquals(FUTSAL_GRADES, ['intro', 'beginner', 'intermediate', 'advanced', 'elite']);
});

Deno.test('regionCodeFromLabel maps 한글 권역명 → RegionCode', () => {
  assertEquals(regionCodeFromLabel('광주'), 'gwangju');
  assertEquals(regionCodeFromLabel('전남'), 'jeonnam');
  assertEquals(regionCodeFromLabel('수도권'), 'seoul_metro');
  assertEquals(regionCodeFromLabel(' 광주 '), 'gwangju'); // trim
  assertEquals(regionCodeFromLabel('없는지역'), null);
  assertEquals(regionCodeFromLabel(''), null);
  assertEquals(regionCodeFromLabel(null), null);
  assertEquals(regionCodeFromLabel(undefined), null);
});

Deno.test('shared enums expose tennis org and region catalogs', () => {
  assertEquals(TENNIS_ORGS, [
    'kta',
    'kato',
    'kata',
    'ktfs',
    'kstf',
    'kssta',
    'kasta',
    'gj',
    'jn',
    'local',
  ]);
  assertEquals(REGION_CODES, [
    'gwangju',
    'jeonnam',
    'seoul_metro',
    'busan_ulsan_gn',
    'daegu_gb',
    'chungcheong',
    'gangwon',
    'jeju',
  ]);
});

Deno.test('shared enums expose entry fee units', () => {
  assertEquals(ENTRY_FEE_UNITS, ['per_team', 'per_person']);
});

// ─── isValidGrade ────────────────────────────────────────────

Deno.test('isValidGrade accepts tennis legacy grades', () => {
  assertEquals(isValidGrade('tennis', 'under1y'), true);
  assertEquals(isValidGrade('tennis', 'over5y'), true);
});

Deno.test('isValidGrade accepts tennis division codes', () => {
  assertEquals(isValidGrade('tennis', 'gj_m_gold'), true);
  assertEquals(isValidGrade('tennis', 'kta_m_open'), true);
  assertEquals(isValidGrade('tennis', 'kata_3'), true);
});

Deno.test('isValidGrade rejects invalid tennis grades', () => {
  assertEquals(isValidGrade('tennis', 'diamond'), false);
  assertEquals(isValidGrade('tennis', ''), false);
  assertEquals(isValidGrade('tennis', 'beginner'), false);
});

Deno.test('isValidGrade accepts futsal grades', () => {
  assertEquals(isValidGrade('futsal', 'intro'), true);
  assertEquals(isValidGrade('futsal', 'beginner'), true);
  assertEquals(isValidGrade('futsal', 'advanced'), true);
  assertEquals(isValidGrade('futsal', 'elite'), true);
});

Deno.test('isValidGrade rejects invalid futsal grades', () => {
  assertEquals(isValidGrade('futsal', 'under1y'), false);
  assertEquals(isValidGrade('futsal', 'gj_m_gold'), false);
});

// ─── canEnter ────────────────────────────────────────────────

Deno.test('canEnter returns true when grade is in eligible list', () => {
  assertEquals(canEnter('gj_m_gold', ['gj_m_open', 'gj_m_gold', 'gj_m_general']), true);
});

Deno.test('canEnter returns false when grade is not in eligible list', () => {
  assertEquals(canEnter('gj_m_rookie', ['gj_m_open', 'gj_m_gold']), false);
});

Deno.test('canEnter handles empty eligible list', () => {
  assertEquals(canEnter('gj_m_gold', []), false);
});

// ─── rankOf ──────────────────────────────────────────────────

Deno.test('rankOf returns correct tennis rank', () => {
  assertEquals(rankOf('tennis', 'under1y'), 0);
  assertEquals(rankOf('tennis', 'over5y'), 3);
});

Deno.test('rankOf returns correct futsal rank', () => {
  assertEquals(rankOf('futsal', 'intro'), 0);
  assertEquals(rankOf('futsal', 'beginner'), 1);
  assertEquals(rankOf('futsal', 'advanced'), 3);
  assertEquals(rankOf('futsal', 'elite'), 4);
});

Deno.test('rankOf returns null for division codes (no rank mapping)', () => {
  assertEquals(rankOf('tennis', 'gj_m_gold'), null);
});

// ─── getDivisionsForOrg / getDivisionLabel ───────────────────

Deno.test('getDivisionsForOrg returns divisions for gj', () => {
  const gj = getDivisionsForOrg('gj');
  assertEquals(gj.length > 0, true);
  assertEquals(gj.every((d) => d.org === 'gj'), true);
});

Deno.test('getDivisionLabel returns label or fallback', () => {
  assertEquals(getDivisionLabel('gj_m_gold'), '골드부');
  assertEquals(getDivisionLabel('unknown_code'), 'unknown_code');
});

// ─── parseDivisionCodes ──────────────────────────────────────

Deno.test('parseDivisionCodes splits comma-separated codes', () => {
  assertEquals(
    parseDivisionCodes('gj_m_gold,jn_m_gold,kta_m_gold'),
    ['gj_m_gold', 'jn_m_gold', 'kta_m_gold'],
  );
});

Deno.test('parseDivisionCodes trims whitespace around codes', () => {
  assertEquals(
    parseDivisionCodes(' gj_m_gold , jn_m_gold '),
    ['gj_m_gold', 'jn_m_gold'],
  );
});

Deno.test('parseDivisionCodes drops empty segments', () => {
  assertEquals(
    parseDivisionCodes('gj_m_gold,,jn_m_gold,'),
    ['gj_m_gold', 'jn_m_gold'],
  );
});

Deno.test('parseDivisionCodes drops format-invalid codes (^[a-z0-9_]+$)', () => {
  // 대문자, 하이픈, 공백포함, SQL 메타문자 등은 형식 불일치로 제거.
  assertEquals(
    parseDivisionCodes("gj_m_gold,GJ_M_GOLD,bad-code,bad code,kta_3,'); DROP"),
    ['gj_m_gold', 'kta_3'],
  );
});

Deno.test('parseDivisionCodes returns null for empty / null / undefined', () => {
  assertEquals(parseDivisionCodes(''), null);
  assertEquals(parseDivisionCodes(null), null);
  assertEquals(parseDivisionCodes(undefined), null);
});

Deno.test('parseDivisionCodes returns null when all segments are invalid/empty', () => {
  assertEquals(parseDivisionCodes(',  , ,'), null);
  assertEquals(parseDivisionCodes('BAD,also-bad'), null);
});

// ─── parseRecruiting ─────────────────────────────────────────

Deno.test('parseRecruiting accepts open / closed', () => {
  assertEquals(parseRecruiting('open'), 'open');
  assertEquals(parseRecruiting('closed'), 'closed');
});

Deno.test('parseRecruiting rejects uppercase / mixed case (no normalization)', () => {
  assertEquals(parseRecruiting('OPEN'), null);
  assertEquals(parseRecruiting('Closed'), null);
  assertEquals(parseRecruiting(' open '), null); // no trim — exact match only
});

Deno.test('parseRecruiting rejects typos / unknown values', () => {
  assertEquals(parseRecruiting('opened'), null);
  assertEquals(parseRecruiting('close'), null);
  assertEquals(parseRecruiting('recruiting'), null);
});

Deno.test('parseRecruiting returns null for empty / null / undefined / non-string', () => {
  assertEquals(parseRecruiting(''), null);
  assertEquals(parseRecruiting(null), null);
  assertEquals(parseRecruiting(undefined), null);
  assertEquals(parseRecruiting(123), null);
});

// ─── isValidPlayerOrigin ─────────────────────────────────────

Deno.test('isValidPlayerOrigin accepts valid origins', () => {
  assertEquals(isValidPlayerOrigin('elementary'), true);
  assertEquals(isValidPlayerOrigin('professional'), true);
  assertEquals(isValidPlayerOrigin('instructor'), true);
});

Deno.test('isValidPlayerOrigin rejects invalid values', () => {
  assertEquals(isValidPlayerOrigin('pro'), false);
  assertEquals(isValidPlayerOrigin(''), false);
});
