/**
 * Intent 분류기 엣지 케이스 테스트.
 *
 * intent_test.ts 가 정형 질문 14건 + 우선순위/날짜/routing 을 커버하므로,
 * 여기서는 커버되지 않는 엣지 케이스에 집중한다:
 *   - 한국어 날짜 단축 표현 ("이번달", "내일", "오늘", "금일", "금주")
 *   - 다중 종목 질의 (첫 매칭 우선 동작)
 *   - 지역 추출 엣지 케이스
 *   - confidence 경계값
 *   - 빈/비정상 입력
 */
import { assertEquals } from 'std/assert/mod.ts';
import {
  buildEmbeddingResult,
  buildFallbackResult,
  classifyByRule,
  extractDateRange,
  extractSlots,
} from '../_shared/intent.ts';

// 고정 시각: KST 2026-06-15(월) 12:00.
const FIXED_NOW = new Date('2026-06-15T03:00:00.000Z');

// ---- 한국어 날짜 단축 표현 ----

Deno.test('extractDateRange: "내일" → 다음 날 하루', () => {
  const r = extractDateRange('내일 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-06-16', to: '2026-06-16' });
});

Deno.test('extractDateRange: "오늘" → 당일 하루', () => {
  const r = extractDateRange('오늘 대회 있어?', FIXED_NOW);
  assertEquals(r, { from: '2026-06-15', to: '2026-06-15' });
});

Deno.test('extractDateRange: "금일" → 당일 하루 (오늘 동의어)', () => {
  const r = extractDateRange('금일 일정', FIXED_NOW);
  assertEquals(r, { from: '2026-06-15', to: '2026-06-15' });
});

Deno.test('extractDateRange: "금주" → 이번 주 월~일', () => {
  // 2026-06-15 는 월요일 → 이번 주 = 06-15(월)~06-21(일)
  const r = extractDateRange('금주 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-06-15', to: '2026-06-21' });
});

Deno.test('extractDateRange: 단독 "5월" → 해당 월 전체', () => {
  const r = extractDateRange('5월 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-05-01', to: '2026-05-31' });
});

Deno.test('extractDateRange: "12월" → 12월 전체', () => {
  const r = extractDateRange('12월 대회 알려줘', FIXED_NOW);
  assertEquals(r, { from: '2026-12-01', to: '2026-12-31' });
});

Deno.test('extractDateRange: "6월 1일" → 단일 날짜', () => {
  const r = extractDateRange('6월 1일 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-06-01', to: '2026-06-01' });
});

Deno.test('extractDateRange: "주말" → 이번 주 토~일', () => {
  // 월요일 기준 → 토=06-20, 일=06-21
  const r = extractDateRange('주말 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-06-20', to: '2026-06-21' });
});

Deno.test('extractDateRange: "다음주" (공백 없이) → 다음 주 월~일', () => {
  const r = extractDateRange('다음주 대회', FIXED_NOW);
  assertEquals(r, { from: '2026-06-22', to: '2026-06-28' });
});

// ---- 다중 종목 질의 (첫 매칭 우선) ----

Deno.test('extractSlots: 다중 종목 "테니스랑 풋살" → 첫 매칭 tennis', () => {
  const slots = extractSlots('테니스랑 풋살 대회 알려줘', FIXED_NOW);
  assertEquals(slots.sport, 'tennis');
});

Deno.test('extractSlots: 다중 종목 "풋살이나 테니스" → 첫 매칭 futsal 아닌 tennis (regex 순서)', () => {
  // extractSport 내부에서 tennis 패턴을 먼저 검사하므로 '테니스'가 문자열에 있으면 tennis.
  const slots = extractSlots('풋살이나 테니스 대회', FIXED_NOW);
  assertEquals(slots.sport, 'tennis');
});

Deno.test('extractSlots: 풋살만 언급 → futsal', () => {
  const slots = extractSlots('풋살 대회 일정', FIXED_NOW);
  assertEquals(slots.sport, 'futsal');
});

// ---- 지역 추출 엣지 케이스 ----

Deno.test('extractSlots: "제주" → jeju', () => {
  const slots = extractSlots('제주 테니스 대회', FIXED_NOW);
  assertEquals(slots.region, 'jeju');
});

Deno.test('extractSlots: "강원" → gangwon', () => {
  const slots = extractSlots('강원 대회 있나요', FIXED_NOW);
  assertEquals(slots.region, 'gangwon');
});

Deno.test('extractSlots: "대전" → chungcheong', () => {
  const slots = extractSlots('대전 풋살 대회', FIXED_NOW);
  assertEquals(slots.region, 'chungcheong');
});

Deno.test('extractSlots: "부산" → busan_ulsan_gn', () => {
  const slots = extractSlots('부산 대회', FIXED_NOW);
  assertEquals(slots.region, 'busan_ulsan_gn');
});

Deno.test('extractSlots: "대구" → daegu_gb', () => {
  const slots = extractSlots('대구 테니스', FIXED_NOW);
  assertEquals(slots.region, 'daegu_gb');
});

Deno.test('extractSlots: 영문 region code "gwangju" 직접 매칭', () => {
  const slots = extractSlots('gwangju 대회 알려줘', FIXED_NOW);
  assertEquals(slots.region, 'gwangju');
});

Deno.test('extractSlots: 지역 없는 질문 → region undefined', () => {
  const slots = extractSlots('대회 알려줘', FIXED_NOW);
  assertEquals(slots.region, undefined);
});

// ---- confidence 경계값 ----

Deno.test('buildEmbeddingResult: similarity > 1 → clamped to 1', () => {
  const r = buildEmbeddingResult('tournament_search', 1.5, {});
  assertEquals(r.confidence, 1);
});

Deno.test('buildEmbeddingResult: similarity < 0 → clamped to 0', () => {
  const r = buildEmbeddingResult('tournament_search', -0.3, {});
  assertEquals(r.confidence, 0);
});

Deno.test('buildFallbackResult: confidence always 0', () => {
  const r = buildFallbackResult({ sport: 'tennis' });
  assertEquals(r.confidence, 0);
  assertEquals(r.method, 'fallback');
  assertEquals(r.intent, 'free_chat');
});

// ---- 빈/비정상 입력 ----

Deno.test('classifyByRule: 빈 문자열 → null', () => {
  assertEquals(classifyByRule(''), null);
});

Deno.test('classifyByRule: 공백만 → null', () => {
  assertEquals(classifyByRule('   '), null);
});

Deno.test('extractSlots: 빈 문자열 → 빈 슬롯', () => {
  const slots = extractSlots('', FIXED_NOW);
  assertEquals(slots, {});
});

Deno.test('extractDateRange: 빈 문자열 → undefined', () => {
  assertEquals(extractDateRange('', FIXED_NOW), undefined);
});

Deno.test('extractDateRange: 무관한 텍스트 → undefined', () => {
  assertEquals(extractDateRange('안녕하세요 반갑습니다', FIXED_NOW), undefined);
});

Deno.test('extractDateRange: 범위 밖 월 "13월" → undefined (매칭은 되나 validation 실패)', () => {
  // "13월" → monthOnly regex 매치 시 month=13 → 1~12 범위 밖 → undefined
  assertEquals(extractDateRange('13월 대회', FIXED_NOW), undefined);
});

Deno.test('extractSlots: 특수문자만 입력 → 빈 슬롯', () => {
  const slots = extractSlots('!@#$%^&*()', FIXED_NOW);
  assertEquals(slots, {});
});
