import { assertEquals, assertFalse } from 'std/assert/mod.ts';

import {
  parseGenderPreference,
  parseMeetingDays,
  parseMonthlyFee,
  parseWebsite,
} from '../clubs-create/validation.ts';

Deno.test('clubs-create meeting days validates and deduplicates', () => {
  assertEquals(parseMeetingDays(['월', '수', '월']), {
    ok: true,
    value: ['월', '수'],
  });
  assertFalse(parseMeetingDays(['월요일']).ok);
  assertFalse(parseMeetingDays('월').ok);
});

Deno.test('clubs-create monthly fee accepts only the shared range', () => {
  assertEquals(parseMonthlyFee(undefined), { ok: true, value: null });
  assertEquals(parseMonthlyFee(0), { ok: true, value: 0 });
  assertEquals(parseMonthlyFee(1_000_000), { ok: true, value: 1_000_000 });
  assertFalse(parseMonthlyFee(-1).ok);
  assertFalse(parseMonthlyFee(1_000_001).ok);
  assertFalse(parseMonthlyFee(1.5).ok);
  assertFalse(parseMonthlyFee('30000').ok);
});

Deno.test('clubs-create gender preference accepts known codes only', () => {
  assertEquals(parseGenderPreference(null), { ok: true, value: null });
  assertEquals(parseGenderPreference('mixed'), { ok: true, value: 'mixed' });
  assertFalse(parseGenderPreference('other').ok);
});

Deno.test('clubs-create website accepts only HTTP(S) URLs', () => {
  assertEquals(parseWebsite(undefined), { ok: true, value: null });
  assertEquals(parseWebsite('https://example.com/club'), {
    ok: true,
    value: 'https://example.com/club',
  });
  assertFalse(parseWebsite('example.com').ok);
  assertFalse(parseWebsite('ftp://example.com').ok);
  assertFalse(parseWebsite(123).ok);
});
