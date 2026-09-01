import { assert, assertEquals, assertRejects } from 'std/assert/mod.ts';

import { sendSms, type SolapiConfig } from '../_shared/solapi.ts';

// 이 어댑터는 돈(발송 요금)과 보안(HMAC 서명)이 동시에 걸린 자리다. 특히 솔라피는
// 개별 메시지가 반려돼도 HTTP 200 을 주기 때문에, 그 분기를 놓치면 "안 나간 문자"가
// 조용히 성공으로 기록된다. 여기서 그 두 가지를 고정한다.

const CFG: SolapiConfig = {
  apiKey: 'TESTKEY',
  apiSecret: 'TESTSECRET',
  from: '16661042',
};

/** 테스트가 구현과 같은 실수를 하지 않도록 서명을 독립적으로 다시 계산한다. */
async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
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

function stubFetch(response: Response): { calls: Array<{ url: string; init?: RequestInit }> } {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return Promise.resolve(response.clone());
  }) as typeof fetch;
  return { calls };
}

Deno.test('sendSms: Authorization 은 hex 서명을 담은 HMAC-SHA256 형식이다', async () => {
  const originalFetch = globalThis.fetch;
  const { calls } = stubFetch(
    new Response(JSON.stringify({ failedMessageList: [] }), { status: 200 }),
  );
  try {
    await sendSms(CFG, '01012345678', '[올라운드] 인증번호 123456');

    assertEquals(calls.length, 1);
    const auth = new Headers(calls[0].init?.headers).get('Authorization') ?? '';
    const m = auth.match(
      /^HMAC-SHA256 apiKey=TESTKEY, date=(\S+), salt=([0-9A-Za-z]{32}), signature=([0-9a-f]{64})$/,
    );
    // signature 가 44자 base64 로 돌아가면 SENS 규격으로 되돌아간 것이고 솔라피는 401 을 준다.
    assert(m, `Authorization 형식이 어긋났다: ${auth}`);

    // 형식만 보면 서명 입력이 틀려도(예: date+salt 가 아닌 다른 문자열) 통과한다.
    // 실제 서명값을 여기서 다시 계산해 맞춰본다.
    const [, date, salt, signature] = m;
    assertEquals(signature, await hmacHex(CFG.apiSecret, date + salt));

    const body = JSON.parse(String(calls[0].init?.body));
    assertEquals(body.messages[0].from, '16661042');
    assertEquals(body.messages[0].to, '01012345678');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('sendSms: HTTP 200 이어도 failedMessageList 가 차 있으면 실패로 본다', async () => {
  const originalFetch = globalThis.fetch;
  stubFetch(
    new Response(
      JSON.stringify({
        failedMessageList: [{
          statusCode: '1030',
          statusMessage: '잔액이 부족합니다',
          to: '01012345678',
        }],
      }),
      { status: 200 },
    ),
  );
  try {
    const err = await assertRejects(
      () => sendSms(CFG, '01012345678', '[올라운드] 인증번호 123456'),
      Error,
    );
    assert(err.message.includes('1030'), `상태코드가 빠졌다: ${err.message}`);
    // 예외 메시지는 호출부가 로그에 남긴다. 수신번호가 섞이면 개인정보가 로그로 샌다.
    assert(!err.message.includes('01012345678'), `수신번호가 예외로 샜다: ${err.message}`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('sendSms: HTTP 200 이어도 본문을 해석 못 하면 실패로 본다', async () => {
  const originalFetch = globalThis.fetch;
  // 프록시·게이트웨이가 끼어들면 200 에 HTML 이 실려 오기도 한다. 이때 발송 여부는 알 수 없다.
  stubFetch(new Response('<html>gateway</html>', { status: 200 }));
  try {
    await assertRejects(
      () => sendSms(CFG, '01012345678', '[올라운드] 인증번호 123456'),
      Error,
      'unparsable',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('sendSms: 실패 목록이 비어도 registeredFailed 가 있으면 실패로 본다', async () => {
  const originalFetch = globalThis.fetch;
  stubFetch(
    new Response(
      JSON.stringify({
        failedMessageList: [],
        groupInfo: { count: { total: 1, registeredSuccess: 0, registeredFailed: 1 } },
      }),
      { status: 200 },
    ),
  );
  try {
    const err = await assertRejects(
      () => sendSms(CFG, '01012345678', '[올라운드] 인증번호 123456'),
      Error,
    );
    assert(
      err.message.includes('registeredFailed'),
      `집계 실패를 못 잡았다: ${err.message}`,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('sendSms: HTTP 실패는 상태코드만 노출한다', async () => {
  const originalFetch = globalThis.fetch;
  stubFetch(
    new Response(JSON.stringify({ errorMessage: '01012345678 잘못된 수신번호' }), { status: 400 }),
  );
  try {
    const err = await assertRejects(
      () => sendSms(CFG, '01012345678', '[올라운드] 인증번호 123456'),
      Error,
    );
    assertEquals(err.message, 'SOLAPI 400');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
