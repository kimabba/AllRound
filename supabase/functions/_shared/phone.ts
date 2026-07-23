// 전화번호 정규화·해시·OTP 생성. 원문 번호는 어디에도 저장하지 않는다.
// pepper 는 Edge Function env(PHONE_HASH_PEPPER)에서만 읽으며 DB·로그에 노출 금지.

const enc = new TextEncoder();

/**
 * 한국 휴대폰 번호를 E.164(+8210XXXXXXXX)로 정규화한다.
 * 010-1234-5678 / 01012345678 / +821012345678 이 모두 같은 값이 되어야
 * phone_hash unique 제약이 의미를 갖는다. 형식이 어긋나면 throw.
 */
export function normalizeE164Kr(raw: string): string {
  let d = raw.replace(/[^\d]/g, '');
  if (d.startsWith('82')) d = d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  if (!/^\d{9,10}$/.test(d)) throw new Error('INVALID_PHONE');
  return `+82${d}`;
}

/** E.164 → SENS 발송용 국내 형식(01012345678). */
export function toDomesticKr(e164: string): string {
  return `0${e164.replace(/^\+82/, '')}`;
}

async function hmacHex(pepper: string, msg: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(msg));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// 도메인 분리 단일 pepper: phone/code 해시가 서로 섞이지 않는다.
export const hashPhone = (e164: string, pepper: string): Promise<string> =>
  hmacHex(pepper, `phone:${e164}`);
export const hashCode = (code: string, pepper: string): Promise<string> =>
  hmacHex(pepper, `code:${code}`);

/** 암호학적 난수 6자리 OTP. */
export function generateOtp(): string {
  // ponytail: 2^32 % 10^6 로 인한 modulo bias 는 6자리 OTP 엔 무의미(공격 방어선은 attempts 잠금).
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, '0');
}
