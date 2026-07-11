/**
 * 크롤러 파싱 로직 엣지 케이스 테스트.
 *
 * crawler_extract_test.ts 가 기본 날짜/마감일/장소/요강 추출을 커버하므로,
 * 여기서는 커버되지 않는 엣지 케이스에 집중한다:
 *   - 날짜 필드 누락/비정상
 *   - 참가비(entry_fee) 파싱은 현재 크롤러 미구현 (정적 파싱 불가)
 *   - 빈 HTML 테이블
 *   - 요강 추출 비정상 형식
 *   - mapDivisionsByDict 엣지 케이스
 */
import { assertEquals } from 'std/assert/mod.ts';
import { DOMParser } from 'deno-dom';
import {
  extractApplicationDeadline,
  extractDate,
  extractRegulationBody,
  extractRegulationFields,
  extractRegulationNotes,
  extractVenue,
} from '../_shared/crawler.ts';
import { mapDivisionsByDict, type DivisionDictRow } from '../_shared/crawler/divisions.ts';

function parseFixture(html: string) {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('fixture parse failed');
  return dom;
}

// ---- 날짜 파싱 엣지 케이스 ----

Deno.test('extractDate: 날짜 없이 텍스트만 → null', () => {
  assertEquals(extractDate('대회 안내입니다. 많은 참가 바랍니다.'), null);
});

Deno.test('extractDate: 여러 날짜 중 첫 유효 날짜 반환', () => {
  const text = '2026년 3월 10일 ~ 2026년 3월 15일';
  assertEquals(extractDate(text), '2026-03-10');
});

Deno.test('extractDate: dot 구분자 "2026.04.05" → 파싱 성공', () => {
  assertEquals(extractDate('일시: 2026.04.05 09시'), '2026-04-05');
});

Deno.test('extractDate: slash 구분자 "2026/04/05" → 파싱 성공', () => {
  assertEquals(extractDate('일시: 2026/04/05'), '2026-04-05');
});

Deno.test('extractDate: 단일 자릿수 월/일 "2026년 1월 5일" → 제로패딩', () => {
  assertEquals(extractDate('2026년 1월 5일'), '2026-01-05');
});

Deno.test('extractDate: 일(day)이 31 초과 → skip', () => {
  // "2026-05-32" 는 day 범위 밖
  assertEquals(extractDate('2026-05-32'), null);
});

Deno.test('extractDate: 월이 0 → skip', () => {
  assertEquals(extractDate('2026-00-15'), null);
});

// ---- 마감일 파싱 엣지 케이스 ----

Deno.test('extractApplicationDeadline: 라벨 없고 "까지" 도 없는 날짜 → null', () => {
  assertEquals(extractApplicationDeadline('2026-04-01 대회 시작'), null);
});

Deno.test('extractApplicationDeadline: 빈 문자열 → null', () => {
  assertEquals(extractApplicationDeadline(''), null);
});

Deno.test('extractApplicationDeadline: "마감일" 라벨 + 한국어 날짜', () => {
  const text = '마감일 2026년 7월 1일까지';
  assertEquals(extractApplicationDeadline(text), '2026-07-01');
});

Deno.test('extractApplicationDeadline: 연속 공백이 있는 라벨', () => {
  const text = '접수  마감   2026-06-30';
  assertEquals(extractApplicationDeadline(text), '2026-06-30');
});

// ---- 장소 추출 엣지 케이스 ----

Deno.test('extractVenue: 빈 문자열 → null', () => {
  assertEquals(extractVenue(''), null);
});

Deno.test('extractVenue: "장 소 : " 공백 포함 라벨 + 스포츠타운', () => {
  const text = '장 소 : 영암종합스포츠타운';
  assertEquals(extractVenue(text), '영암종합스포츠타운');
});

Deno.test('extractVenue: 체육관 접미사 매칭', () => {
  assertEquals(extractVenue('광주시민체육관에서 개최'), '광주시민체육관');
});

// ---- 빈/비정상 HTML 테이블 ----

Deno.test('extractRegulationFields: 빈 테이블 → 빈 배열', () => {
  const dom = parseFixture('<html><body><table></table></body></html>');
  assertEquals(extractRegulationFields(dom), []);
});

Deno.test('extractRegulationFields: 테이블 없음 → 빈 배열', () => {
  const dom = parseFixture('<html><body><p>내용만 있는 페이지</p></body></html>');
  assertEquals(extractRegulationFields(dom), []);
});

Deno.test('extractRegulationFields: td 가 1칸뿐인 행 → skip (2칸 필요)', () => {
  const dom = parseFixture(`
    <html><body><table>
      <tr><td>장소</td></tr>
      <tr><td>주최</td><td>영암군 체육회</td></tr>
    </table></body></html>
  `);
  const fields = extractRegulationFields(dom);
  // 장소 행은 td 1개라 skip, 주최만 추출
  assertEquals(fields, [{ label: '주최', value: '영암군 체육회' }]);
});

Deno.test('extractRegulationBody: 빈 테이블 → null', () => {
  const dom = parseFixture('<html><body><table></table></body></html>');
  assertEquals(extractRegulationBody(dom), null);
});

Deno.test('extractRegulationNotes: 빈 문서 → 빈 배열', () => {
  const dom = parseFixture('<html><body></body></html>');
  assertEquals(extractRegulationNotes(dom), []);
});

// ---- mapDivisionsByDict 엣지 케이스 ----

// gj 부서 사전 fixture (P1 tennis_divisions 시드 미러, code 기준 정렬)
const GJ_DICT: DivisionDictRow[] = [
  { code: 'gj_m_open', synonyms: ['오픈부', '남자오픈', '오픈'], label_ko: '오픈부' },
  { code: 'gj_m_gold', synonyms: ['골드부', '골드'], label_ko: '골드부' },
  { code: 'gj_m_general', synonyms: ['남자일반부', '일반부', '남자일반'], label_ko: '일반부' },
  { code: 'gj_m_instructor', synonyms: ['지도자부', '지도자'], label_ko: '지도자부' },
  { code: 'gj_m_masters', synonyms: ['마스터즈부', '마스터즈'], label_ko: '마스터즈부' },
  { code: 'gj_m_rookie', synonyms: ['남자신인부', '신인부', '신인'], label_ko: '신인부' },
  { code: 'gj_m_veteran', synonyms: ['베테랑부', '베테랑'], label_ko: '베테랑부' },
  { code: 'gj_m_beginner', synonyms: ['초급자부', '비입상자부', '초급자'], label_ko: '초급자부' },
  { code: 'gj_w_open', synonyms: ['여자오픈부', '여자오픈'], label_ko: '여자오픈부' },
  { code: 'gj_w_winner', synonyms: ['우승자부', '여자우승자', '국화', '금배'], label_ko: '여자우승자부' },
  { code: 'gj_w_rookie', synonyms: ['여자신인부', '여자신인', '개나리'], label_ko: '여자신인부' },
  { code: 'gj_couple', synonyms: ['부부부', '부부'], label_ko: '부부부' },
  { code: 'gj_cross', synonyms: ['크로스'], label_ko: '크로스대회' },
];
const sorted = (a: string[]) => [...a].sort();

Deno.test('mapDivisionsByDict: 미매칭 → 비움 + unmapped=true (기본값 폴백 없음)', () => {
  const r = mapDivisionsByDict('제5회 영암 대회', GJ_DICT);
  assertEquals(r.codes, []);
  assertEquals(r.unmapped, true);
});

Deno.test('mapDivisionsByDict: "골드부" 단일 매칭', () => {
  const r = mapDivisionsByDict('골드부 경기일정', GJ_DICT);
  assertEquals(r.codes, ['gj_m_gold']);
  assertEquals(r.label, '골드부');
  assertEquals(r.unmapped, false);
});

Deno.test('mapDivisionsByDict: 복수 매칭 — "오픈" substring이 여자오픈부에도 걸림 (집합 동치)', () => {
  const r = mapDivisionsByDict('골드부 일반부 여자오픈부 대회', GJ_DICT);
  assertEquals(sorted(r.codes), sorted(['gj_m_open', 'gj_m_gold', 'gj_m_general', 'gj_w_open']));
});

Deno.test('mapDivisionsByDict: "부부부" 매칭', () => {
  const r = mapDivisionsByDict('부부부 대회', GJ_DICT);
  assertEquals(r.codes, ['gj_couple']);
});

Deno.test('mapDivisionsByDict: "개나리"(synonym) → 여자신인부', () => {
  const r = mapDivisionsByDict('개나리부 대회', GJ_DICT);
  assertEquals(r.codes, ['gj_w_rookie']);
});

Deno.test('mapDivisionsByDict: 빈 사전 → unmapped', () => {
  const r = mapDivisionsByDict('골드부', []);
  assertEquals(r.codes, []);
  assertEquals(r.unmapped, true);
});
