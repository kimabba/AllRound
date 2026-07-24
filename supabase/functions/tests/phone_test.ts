import { assert, assertEquals, assertNotEquals, assertThrows } from 'std/assert/mod.ts';

import {
  generateOtp,
  hashCode,
  hashPhone,
  normalizeE164Kr,
  toDomesticKr,
} from '../_shared/phone.ts';

Deno.test('normalizeE164Kr: 표기가 달라도 같은 번호는 같은 E.164', () => {
  const forms = ['010-1234-5678', '01012345678', '+82 10 1234 5678', '821012345678', '1012345678'];
  for (const f of forms) {
    assertEquals(normalizeE164Kr(f), '+821012345678', `실패한 입력: ${f}`);
  }
});

Deno.test('normalizeE164Kr: 형식 오류·비휴대폰 번호는 throw', () => {
  const bad = [
    '',
    '123',
    '010-1234',
    'abcd',
    '0108212345678901',
    '02-1234-5678', // 유선(서울) — SMS 불가
    '070-1234-5678', // 인터넷전화
    '015-1234-5678', // 이동통신 접두 아님
    '010-123-4567', // 010 은 가입자번호 8자리여야 함
  ];
  for (const value of bad) {
    assertThrows(() => normalizeE164Kr(value), Error, 'INVALID_PHONE');
  }
});

Deno.test('normalizeE164Kr: 구 이동통신 접두(011·016~019)도 허용', () => {
  assertEquals(normalizeE164Kr('011-234-5678'), '+82112345678');
  assertEquals(normalizeE164Kr('019-123-4567'), '+82191234567');
});

Deno.test('toDomesticKr: E.164 → 국내 발송 형식', () => {
  assertEquals(toDomesticKr('+821012345678'), '01012345678');
});

Deno.test('hashPhone: 같은 입력·pepper 는 결정적, pepper 다르면 달라짐', async () => {
  const a = await hashPhone('+821012345678', 'pepper-1');
  const b = await hashPhone('+821012345678', 'pepper-1');
  const c = await hashPhone('+821012345678', 'pepper-2');
  assertEquals(a, b);
  assertNotEquals(a, c);
  assertEquals(a.length, 64); // SHA-256 hex
});

Deno.test('도메인 분리: phone/code 해시는 같은 값이라도 섞이지 않음', async () => {
  // 코드 '123456' 과 번호가 우연히 같은 문자열이어도 해시 공간이 분리됨.
  const p = await hashPhone('x', 'pep');
  const c = await hashCode('x', 'pep');
  assertNotEquals(p, c);
});

Deno.test('generateOtp: 항상 6자리 숫자', () => {
  for (let i = 0; i < 200; i++) {
    assert(/^\d{6}$/.test(generateOtp()));
  }
});
