import { assertEquals, assertFalse } from 'std/assert/mod.ts';

import { ageGroupFromBirthDate, parseInquiryRequest } from '../clubs-inquiries/validation.ts';

Deno.test('clubs-inquiries accepts a new pre-join inquiry', () => {
  assertEquals(parseInquiryRequest({ club_id: 'club-1', body: '  주말 시간이 궁금해요.  ' }), {
    ok: true,
    value: {
      clubId: 'club-1',
      threadId: null,
      body: '주말 시간이 궁금해요.',
    },
  });
});

Deno.test('clubs-inquiries accepts a reply and rejects ambiguous targets', () => {
  assertEquals(parseInquiryRequest({ thread_id: 'thread-1', body: '답변입니다.' }), {
    ok: true,
    value: {
      clubId: null,
      threadId: 'thread-1',
      body: '답변입니다.',
    },
  });
  assertFalse(parseInquiryRequest({ club_id: 'c', thread_id: 't', body: '문의' }).ok);
  assertFalse(parseInquiryRequest({ body: '문의' }).ok);
});

Deno.test('clubs-inquiries validates trimmed message length', () => {
  assertFalse(parseInquiryRequest({ club_id: 'c', body: '   ' }).ok);
  assertFalse(parseInquiryRequest({ club_id: 'c', body: 'a'.repeat(1001) }).ok);
  assertEquals(parseInquiryRequest({ club_id: 'c', body: 'a'.repeat(1000) }).ok, true);
});

Deno.test('clubs-inquiries exposes only a derived requester age group', () => {
  const today = new Date('2026-07-22T00:00:00Z');
  assertEquals(ageGroupFromBirthDate('1992-07-21', today), '30대');
  assertEquals(ageGroupFromBirthDate('2015-01-01', today), null);
  assertEquals(ageGroupFromBirthDate(null, today), null);
});

Deno.test('age group counts the birthday itself but not the day before', () => {
  const today = new Date('2026-07-22T00:00:00Z');
  // 생일 당일(경계 포함)은 지난 것으로 판정 → 승급
  assertEquals(ageGroupFromBirthDate('1986-07-22', today), '40대');
  // 하루 전이면 아직 안 지남 → age-1 로 연령대가 갈라짐
  assertEquals(ageGroupFromBirthDate('1986-07-23', today), '30대');
});

Deno.test('age group enforces the 14~120 eligibility bounds', () => {
  const today = new Date('2026-07-22T00:00:00Z');
  assertEquals(ageGroupFromBirthDate('2012-07-22', today), '10대'); // 정확히 14세 통과
  assertEquals(ageGroupFromBirthDate('2012-07-23', today), null); // 13세 미달
  assertEquals(ageGroupFromBirthDate('1906-07-22', today), '120대'); // 120세 통과
  assertEquals(ageGroupFromBirthDate('1905-07-22', today), null); // 121세 초과
});

Deno.test('age group evaluates the month comparison in both directions', () => {
  const today = new Date('2026-07-22T00:00:00Z');
  assertEquals(ageGroupFromBirthDate('1990-01-01', today), '30대'); // 이전 달 → 지남
  assertEquals(ageGroupFromBirthDate('1986-08-01', today), '30대'); // 이후 달 → 안 지남
});

Deno.test('age group rejects malformed date strings', () => {
  const today = new Date('2026-07-22T00:00:00Z');
  assertEquals(ageGroupFromBirthDate('not-a-date', today), null);
  assertEquals(ageGroupFromBirthDate('1992/07/21', today), null); // 하이픈 구분자 아님
  assertEquals(ageGroupFromBirthDate('1992-07', today), null); // 파트 2개
  assertEquals(ageGroupFromBirthDate('', today), null); // 빈 문자열
});

Deno.test('parse rejects a non-string body as too short', () => {
  assertEquals(parseInquiryRequest({ club_id: 'c', body: 123 }), {
    ok: false,
    message: 'body must be between 1 and 1000 characters',
  });
});

Deno.test('parse treats a whitespace-only id as absent', () => {
  // 공백 club_id + 유효 thread_id → 유효한 단일 타깃
  assertEquals(parseInquiryRequest({ club_id: '   ', thread_id: 't-1', body: '문의' }), {
    ok: true,
    value: { clubId: null, threadId: 't-1', body: '문의' },
  });
  // 공백 club_id 단독 → 타깃 없음 (body 에러가 아니라 타깃 에러가 선행)
  assertEquals(parseInquiryRequest({ club_id: '   ', body: '문의' }), {
    ok: false,
    message: 'Provide exactly one of club_id or thread_id',
  });
  // 비문자열 club_id 도 "없음" 취급
  assertEquals(parseInquiryRequest({ club_id: 123, body: '문의' }), {
    ok: false,
    message: 'Provide exactly one of club_id or thread_id',
  });
});

Deno.test('parse trims ids before returning them', () => {
  assertEquals(parseInquiryRequest({ thread_id: '  t-1  ', body: 'x' }), {
    ok: true,
    value: { clubId: null, threadId: 't-1', body: 'x' },
  });
});

Deno.test('parse rejects non-object payloads', () => {
  for (const payload of [null, ['club-1'], 'club-1']) {
    assertEquals(parseInquiryRequest(payload), {
      ok: false,
      message: 'Invalid JSON object',
    });
  }
});
