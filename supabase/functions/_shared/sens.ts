// 네이버 클라우드 SENS SMS 발송.
// 서명: HMAC-SHA256(secretKey, "POST {path}\n{timestamp}\n{accessKey}") → base64.
// 번호·인증코드 원문은 로그에 남기지 않는다(개인정보보호법 §29).

const enc = new TextEncoder();

export interface SensConfig {
  serviceId: string;
  accessKey: string;
  secretKey: string;
  from: string; // 발신번호(사전 등록된 국내번호)
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

export function sensConfigFromEnv(): SensConfig {
  return {
    serviceId: requireEnv('SENS_SERVICE_ID'),
    accessKey: requireEnv('SENS_ACCESS_KEY'),
    secretKey: requireEnv('SENS_SECRET_KEY'),
    from: requireEnv('SENS_FROM'),
  };
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
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

/** 국내번호 to(01012345678)로 SMS 1건 발송. 실패 시 throw(상태코드만 노출). */
export async function sendSms(cfg: SensConfig, to: string, content: string): Promise<void> {
  const ts = Date.now().toString();
  const path = `/sms/v2/services/${cfg.serviceId}/messages`;
  const signature = await sign(cfg.secretKey, `POST ${path}\n${ts}\n${cfg.accessKey}`);

  const res = await fetch(`https://sens.apigw.ntruss.com${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'x-ncp-apigw-timestamp': ts,
      'x-ncp-iam-access-key': cfg.accessKey,
      'x-ncp-apigw-signature-v2': signature,
    },
    body: JSON.stringify({
      type: 'SMS',
      from: cfg.from,
      content,
      messages: [{ to }],
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`SENS ${res.status}: ${body.slice(0, 200)}`);
  }
}
