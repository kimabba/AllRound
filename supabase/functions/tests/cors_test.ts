import { assert, assertEquals } from 'std/assert/mod.ts';

import { corsHeaders, errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';

Deno.test('preflight: OPTIONS 요청엔 CORS 응답(ok)', async () => {
  const res = preflight(new Request('https://x', { method: 'OPTIONS' }));
  assert(res instanceof Response);
  assertEquals(res!.status, 200);
  assertEquals(await res!.text(), 'ok');
  assertEquals(
    res!.headers.get('Access-Control-Allow-Origin'),
    corsHeaders['Access-Control-Allow-Origin'],
  );
});

Deno.test('preflight: 비-OPTIONS 요청은 null', () => {
  assertEquals(preflight(new Request('https://x', { method: 'GET' })), null);
  assertEquals(preflight(new Request('https://x', { method: 'POST' })), null);
});

Deno.test('jsonResponse: body 직렬화 + CORS/Content-Type + 기본 200', async () => {
  const res = jsonResponse({ a: 1 });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('Content-Type'), 'application/json');
  assertEquals(
    res.headers.get('Access-Control-Allow-Methods'),
    corsHeaders['Access-Control-Allow-Methods'],
  );
  assertEquals(await res.json(), { a: 1 });
});

Deno.test('jsonResponse: init.status와 커스텀 헤더를 병합', () => {
  const res = jsonResponse({}, { status: 201, headers: { 'X-Test': 'y' } });
  assertEquals(res.status, 201);
  assertEquals(res.headers.get('X-Test'), 'y');
  assertEquals(res.headers.get('Content-Type'), 'application/json');
});

Deno.test('errorResponse: {error, ...extra} 본문 + status', async () => {
  const res = errorResponse('bad', 422, { field: 'name' });
  assertEquals(res.status, 422);
  assertEquals(await res.json(), { error: 'bad', field: 'name' });
});

Deno.test('errorResponse: status 기본값 400', async () => {
  const res = errorResponse('oops');
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, 'oops');
});
