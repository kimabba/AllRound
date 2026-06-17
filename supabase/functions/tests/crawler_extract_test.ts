// crawler_extract_test.ts
// _shared/crawler.ts 의 extractDate / extractApplicationDeadline 단위 테스트.
//
// 회귀 방지 목적:
//   - 한국 협회 사이트의 본문이 한국어 형식 "YYYY년 M월 D일" 를 주로 쓰는데
//     기존 숫자 전용 정규식은 매치하지 못해, 은행 계좌번호 등에서 false-positive
//     날짜가 추출되는 버그가 있었다 (예: "784902-01-022035" → "4902-01-02").
//   - 본 테스트는 한국어 매칭 우선 + 연도 sanity 검증 동작을 고정한다.

import { assert, assertEquals } from 'std/assert/mod.ts';
import { extractApplicationDeadline, extractDate, extractVenue } from '../_shared/crawler.ts';

Deno.test('extractDate parses Korean format first', () => {
  const text = '경기일시 : 2026년 4월 5일(일) 09시~ ...';
  assertEquals(extractDate(text), '2026-04-05');
});

Deno.test('extractDate parses numeric YYYY-MM-DD as fallback', () => {
  const text = '게시일 2026-03-16 14:25:54';
  assertEquals(extractDate(text), '2026-03-16');
});

Deno.test('extractDate rejects out-of-range year (sanity guard)', () => {
  // 은행 계좌번호 "784902-01-022035" → "4902-01-02" false positive.
  // 현재 연도 + 5 초과 → null 반환.
  const text = '입금계좌 : (국민은행 784902-01-022035, 예금주 : 신용관)';
  assertEquals(extractDate(text), null);
});

Deno.test('extractDate prefers in-range Korean date over out-of-range numeric', () => {
  // 한국어 형식 매칭이 먼저 후보로 들어가므로, sanity 통과한 첫 매치를 반환.
  const text = '계좌 784902-01-022035 / 경기일 2026년 5월 10일';
  assertEquals(extractDate(text), '2026-05-10');
});

Deno.test('extractDate rejects nonsense month/day even if year ok', () => {
  // 2026-13-45 는 month/day 범위 밖 → 다음 매치 시도, 없으면 null.
  assertEquals(extractDate('2026-13-45'), null);
});

Deno.test('extractDate returns null on empty / no date', () => {
  assertEquals(extractDate(''), null);
  assertEquals(extractDate('no dates here'), null);
});

Deno.test('extractApplicationDeadline parses Korean format with label', () => {
  const text = '신청기간 : 2026년 3월 16일 ~ 2026년 4월 1일 18시까지';
  const r = extractApplicationDeadline(text);
  // 라벨 직후 첫 매치 → 시작 일자가 들어옴 (기존 동작 보존).
  assertEquals(r, '2026-03-16');
});

Deno.test('extractApplicationDeadline parses numeric with label', () => {
  const text = '접수마감 2026-04-01 까지';
  assertEquals(extractApplicationDeadline(text), '2026-04-01');
});

Deno.test('extractApplicationDeadline parses 까지 with Korean date (no label)', () => {
  const text = '2026년 4월 1일까지 접수합니다.';
  assertEquals(extractApplicationDeadline(text), '2026-04-01');
});

Deno.test('extractApplicationDeadline rejects out-of-range year', () => {
  // 은행 계좌번호 형태가 들어와도 마감일로 채택되지 않아야 함.
  const text = '계좌 784902-01-022035 까지';
  // 라벨 없음 + sanity 실패 → null
  const r = extractApplicationDeadline(text);
  assert(r === null, `expected null, got ${r}`);
});

Deno.test('extractVenue extracts facility name from body (no label)', () => {
  const text = '단체전 예선 배정팀 중 진월국제테니스장은 8시30분 경기시작';
  assertEquals(extractVenue(text), '진월국제테니스장');
});

Deno.test('extractVenue prefers labeled location', () => {
  const text = '일시 2026년 3월 7일 경기장 광주시민테니스장 에서 진행';
  assertEquals(extractVenue(text), '광주시민테니스장');
});

Deno.test('extractVenue returns null when no facility name', () => {
  assertEquals(extractVenue('참가비 입금 안내 function accounting_price_ser()'), null);
});
