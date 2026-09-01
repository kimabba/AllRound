// 솔라피(SOLAPI) SMS 발송.
// 인증: Authorization: HMAC-SHA256 apiKey=…, date=…, salt=…, signature=…
//       signature = HMAC-SHA256(apiSecret, date + salt) 의 hex.
//       (공식 SDK solapi-nodejs `src/lib/authenticator.ts` 와 같은 규격.
//        SENS 는 base64 였으나 솔라피는 hex 다 — 바꿔 쓰면 401 이 난다.)
// 번호·인증코드 원문은 로그에 남기지 않는다(개인정보보호법 §29).

const enc = new TextEncoder();
const SEND_URL = 'https://api.solapi.com/messages/v4/send-many/detail';
const SALT_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

export interface SolapiConfig {
  apiKey: string;
  apiSecret: string;
  from: string; // 발신번호(사전 등록·승인된 국내번호)
}

/** 솔라피 발송 응답 중 실패 판정에 쓰는 부분만 정의한다. */
interface SendResponse {
  failedMessageList?: Array<{ statusCode?: string; statusMessage?: string }>;
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

export function solapiConfigFromEnv(): SolapiConfig {
  return {
    apiKey: requireEnv('SOLAPI_API_KEY'),
    apiSecret: requireEnv('SOLAPI_API_SECRET'),
    from: requireEnv('SOLAPI_FROM'),
  };
}

/** 서명용 nonce. 예측 불가능하기만 하면 되므로 모듈로 편향은 무해하다. */
function randomSalt(size = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(size));
  let out = '';
  for (const b of bytes) out += SALT_ALPHABET[b % SALT_ALPHABET.length];
  return out;
}

async function sign(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** 국내번호 to(01012345678)로 SMS 1건 발송. 실패 시 throw(상태코드만 노출). */
export async function sendSms(
  cfg: SolapiConfig,
  to: string,
  content: string,
): Promise<void> {
  const date = new Date().toISOString();
  const salt = randomSalt();
  const signature = await sign(cfg.apiSecret, date + salt);

  const res = await fetch(SEND_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization':
        `HMAC-SHA256 apiKey=${cfg.apiKey}, date=${date}, salt=${salt}, signature=${signature}`,
    },
    body: JSON.stringify({ messages: [{ to, from: cfg.from, text: content }] }),
  });

  if (!res.ok) {
    // 공급자 오류 본문에는 수신번호·메시지 같은 개인정보가 포함될 수 있다.
    // 호출부가 예외 메시지를 로그에 남기므로 상태코드만 전달한다.
    throw new Error(`SOLAPI ${res.status}`);
  }

  // 솔라피는 개별 메시지가 반려돼도 HTTP 200 을 준다(잔액 부족, 미등록 발신번호 등).
  // 여기서 보지 않으면 "보냈다고 믿었는데 안 나간" 상태가 조용히 성공으로 기록된다.
  const body = (await res.json().catch(() => null)) as SendResponse | null;
  const failed = body?.failedMessageList;
  if (Array.isArray(failed) && failed.length > 0) {
    throw new Error(`SOLAPI send failed: ${failed[0]?.statusCode ?? 'unknown'}`);
  }
}
