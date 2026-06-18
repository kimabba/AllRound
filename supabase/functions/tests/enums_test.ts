import { assertEquals } from 'std/assert/mod.ts';
import {
  canEnter,
  ENTRY_FEE_UNITS,
  FUTSAL_GRADES,
  getDivisionLabel,
  getDivisionsForOrg,
  isValidGrade,
  isValidPlayerOrigin,
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
