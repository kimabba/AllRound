import { assertEquals, assertFalse } from 'std/assert/mod.ts';

import {
  parseGenderPreference,
  parseMeetingDays,
  parseMonthlyFee,
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
