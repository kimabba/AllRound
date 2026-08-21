import { assert, assertEquals } from 'std/assert/mod.ts';

// 회귀 대상: Gemini 호출들이 ?key=... 형태로 API 키를 URL 쿼리스트링에 실었었다. Deno fetch가
// 네트워크 계층에서 실패하면(DNS/TLS 등) 그 URL(키 포함)을 담은 에러를 던지고, 그 원문 메시지가
// semantic-search 500 응답에 그대로 반환됐다. 키는 이제 x-goog-api-key 헤더로만 보낸다.

function stubFetch(response: Response): { calls: Array<{ url: string; init?: RequestInit }> } {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return Promise.resolve(response.clone());
  }) as typeof fetch;
  return { calls };
}

Deno.env.set('GEMINI_API_KEY', 'test-secret-key');

Deno.test('embedText: key는 헤더로만 가고 URL 쿼리스트링에는 없다', async () => {
  const originalFetch = globalThis.fetch;
  const { calls } = stubFetch(
    new Response(JSON.stringify({ embedding: { values: [0.1, 0.2] } }), { status: 200 }),
  );
  try {
    const { embedText } = await import('../_shared/embedding.ts');
    await embedText('hello');
    assertEquals(calls.length, 1);
    assert(!calls[0].url.includes('key='), `URL leaked the key: ${calls[0].url}`);
    assertEquals(
      new Headers(calls[0].init?.headers).get('x-goog-api-key'),
      'test-secret-key',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('embedBatch: key는 헤더로만 가고 URL 쿼리스트링에는 없다', async () => {
  const originalFetch = globalThis.fetch;
  const { calls } = stubFetch(
    new Response(JSON.stringify({ embeddings: [{ values: [0.1] }] }), { status: 200 }),
  );
  try {
    const { embedBatch } = await import('../_shared/embedding.ts');
    await embedBatch(['hello']);
    assertEquals(calls.length, 1);
    assert(!calls[0].url.includes('key='), `URL leaked the key: ${calls[0].url}`);
    assertEquals(
      new Headers(calls[0].init?.headers).get('x-goog-api-key'),
      'test-secret-key',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('generateStructured: key는 헤더로만 가고 URL 쿼리스트링에는 없다', async () => {
  const originalFetch = globalThis.fetch;
  const { calls } = stubFetch(
    new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }] }),
      { status: 200 },
    ),
  );
  try {
    const { generateStructured } = await import('../_shared/gemini.ts');
    await generateStructured('prompt', {});
    assertEquals(calls.length, 1);
    assert(!calls[0].url.includes('key='), `URL leaked the key: ${calls[0].url}`);
    assertEquals(
      new Headers(calls[0].init?.headers).get('x-goog-api-key'),
      'test-secret-key',
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test('streamChat: key는 헤더로만 가고 URL 쿼리스트링에는 없다(alt=sse는 유지)', async () => {
  const originalFetch = globalThis.fetch;
  const { calls } = stubFetch(new Response('', { status: 200 }));
  try {
    const { streamChat } = await import('../_shared/gemini.ts');
    const events = [];
    for await (const ev of streamChat([{ role: 'user', parts: [{ text: 'hi' }] }])) {
      events.push(ev);
    }
    assertEquals(calls.length, 1);
    assert(calls[0].url.includes('alt=sse'), `alt=sse missing: ${calls[0].url}`);
    assert(!calls[0].url.includes('key='), `URL leaked the key: ${calls[0].url}`);
    assertEquals(
      new Headers(calls[0].init?.headers).get('x-goog-api-key'),
      'test-secret-key',
    );
    assertEquals(events[events.length - 1].type, 'done');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
