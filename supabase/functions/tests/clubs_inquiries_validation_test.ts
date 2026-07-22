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
