import { assertEquals } from 'std/assert/mod.ts';
import {
  ENTRY_FEE_UNITS,
  isValidGrade,
  isValidPlayerOrigin,
  parseDivisionCodes,
  parseRecruiting,
  REGION_CODES,
  regionCodeFromLabel,
  TENNIS_ORGS,
} from '../_shared/enums.ts';

// 등급 목록은 DB public.grades 가 정본이라 Edge 에 사본이 없다(#319). 활성 목록은 호출부가
// 조회해 넘기므로, 테스트에서는 DB 조회 결과를 대신할 Set 을 직접 만든다.
const TENNIS_ACTIVE: ReadonlySet<string> = new Set(['under1y', 'y1to3', 'y3to5', 'over5y']);
const FUTSAL_ACTIVE: ReadonlySet<string> = new Set([
  'intro',
  'beginner',
  'intermediate',
  'advanced',
  'elite',
]);

Deno.test('regionCodeFromLabel maps 한글 권역명 → RegionCode', () => {
  assertEquals(regionCodeFromLabel('광주'), 'gwangju');
  assertEquals(regionCodeFromLabel('전남'), 'jeonnam');
  assertEquals(regionCodeFromLabel('서울'), 'seoul');
  assertEquals(regionCodeFromLabel('경기'), 'gyeonggi');
  assertEquals(regionCodeFromLabel('전북'), 'jeonbuk');
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
    'seoul',
    'gyeonggi',
    'incheon',
    'gangwon',
    'daejeon',
    'sejong',
    'chungbuk',
    'chungnam',
    'gwangju',
    'jeonbuk',
    'jeonnam',
    'busan',
    'ulsan',
    'daegu',
    'gyeongbuk',
    'gyeongnam',
    'jeju',
  ]);
});

Deno.test('shared enums expose entry fee units', () => {
  assertEquals(ENTRY_FEE_UNITS, ['per_team', 'per_person']);
});

// ─── isValidGrade ────────────────────────────────────────────

Deno.test('isValidGrade accepts codes present in the DB catalog', () => {
  assertEquals(isValidGrade('tennis', 'under1y', TENNIS_ACTIVE), true);
  assertEquals(isValidGrade('tennis', 'over5y', TENNIS_ACTIVE), true);
  assertEquals(isValidGrade('futsal', 'intro', FUTSAL_ACTIVE), true);
  assertEquals(isValidGrade('futsal', 'elite', FUTSAL_ACTIVE), true);
});

Deno.test('isValidGrade accepts a grade the DB added without a code change', () => {
  // #319 의 핵심: TS 사본이 없으므로 관리자가 추가한 등급도 즉시 통과한다.
  const withNewGrade: ReadonlySet<string> = new Set([...FUTSAL_ACTIVE, 'semi_pro']);
  assertEquals(isValidGrade('futsal', 'semi_pro', withNewGrade), true);
  assertEquals(isValidGrade('futsal', 'semi_pro', FUTSAL_ACTIVE), false);
});

Deno.test('isValidGrade accepts tennis division codes without a catalog entry', () => {
  assertEquals(isValidGrade('tennis', 'gj_m_gold', TENNIS_ACTIVE), true);
  assertEquals(isValidGrade('tennis', 'kta_m_open', TENNIS_ACTIVE), true);
  assertEquals(isValidGrade('tennis', 'kata_3', TENNIS_ACTIVE), true);
});

Deno.test('isValidGrade rejects unknown codes', () => {
  assertEquals(isValidGrade('tennis', 'diamond', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', '', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', 'beginner', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('futsal', 'under1y', FUTSAL_ACTIVE), false);
  // 부서 코드는 테니스 전용 — 풋살에서는 형식이 맞아도 거부.
  assertEquals(isValidGrade('futsal', 'gj_m_gold', FUTSAL_ACTIVE), false);
});

Deno.test('isValidGrade rejects malformed tennis division codes', () => {
  // 조직 접두사만 보던 시절엔 아래가 전부 통과해 eligible_grades 로 들어갔다(codex 1차).
  assertEquals(isValidGrade('tennis', 'gj_', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', 'gj_NOT_REAL', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', "gj_'); DROP", TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', 'gj_m gold', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', '_m_gold', TENNIS_ACTIVE), false);
  assertEquals(isValidGrade('tennis', 'zz_m_gold', TENNIS_ACTIVE), false); // 미등록 조직
});

Deno.test('isValidGrade fails closed on an empty catalog', () => {
  const empty: ReadonlySet<string> = new Set();
  assertEquals(isValidGrade('futsal', 'intro', empty), false);
  // 테니스 부서 코드는 grades 와 무관한 별도 정본(tennis_divisions)이라 형식만 본다.
  assertEquals(isValidGrade('tennis', 'gj_m_gold', empty), true);
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
