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
  // 공식 문서상 count 의 registeredSuccess/registeredFailed 는 항상 오는 숫자 필드다.
  // 접수 결과가 목록이 아니라 이 집계로만 표현되기도 한다.
  groupInfo?: { count?: { registeredSuccess?: number; registeredFailed?: number } };
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
  if (!body || typeof body !== 'object') {
    // 200 인데 우리가 아는 응답이 아니면 발송 여부를 확인할 수 없다.
    // 확인 못 한 것을 성공으로 넘기지 않는다(fail-closed).
    throw new Error('SOLAPI 200: unparsable body');
  }

  const failed = body.failedMessageList;
  if (Array.isArray(failed) && failed.length > 0) {
    // 본문에는 수신번호가 들어 있다. 상태코드만, 그것도 문자열일 때만 밖으로 낸다.
    const code = failed[0]?.statusCode;
    throw new Error(`SOLAPI send failed: ${typeof code === 'string' ? code : 'unknown'}`);
  }

  // 성공은 "성공했다는 증거"가 있을 때만 인정한다. 필드가 빠졌거나 타입이 다르면
  // 발송 여부를 모르는 것이고, 모르는 것은 실패로 본다(fail-closed).
  const count = body.groupInfo?.count;
  if (
    typeof count?.registeredSuccess !== 'number' ||
    typeof count?.registeredFailed !== 'number'
  ) {
    throw new Error('SOLAPI 200: unexpected body shape');
  }
  // 1건 발송이므로 접수 성공이 1 미만이거나 실패가 0 이 아니면 나가지 않은 것이다.
  // `> 0` 이 아니라 `!== 0` 인 이유: 음수 같은 이상값도 우리가 아는 응답이 아니다.
  // 값 자체는 노출하지 않는다 — 응답값이 그대로 로그로 흘러가는 경로를 만들지 않는다.
  if (count.registeredFailed !== 0 || count.registeredSuccess < 1) {
    throw new Error('SOLAPI send rejected');
  }
}
