import { assert, assertEquals } from 'std/assert/mod.ts';

import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  matchOrigin,
  preflight,
  withCors,
} from '../_shared/cors.ts';

Deno.test('preflight: OPTIONS 요청엔 CORS 응답(ok)', async () => {
  const res = preflight(new Request('https://x', { method: 'OPTIONS' }));
  assert(res instanceof Response);
  assertEquals(res!.status, 200);
  assertEquals(await res!.text(), 'ok');
  assertEquals(
    res!.headers.get('Access-Control-Allow-Methods'),
    corsHeaders['Access-Control-Allow-Methods'],
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

// JY-95: 허용 목록이 여럿이라 ACAO 는 요청 Origin 을 되돌려주는 방식이다.
// 목록 밖 오리진에 ACAO 를 붙이면 아무 사이트나 응답을 읽을 수 있으므로, 그 경우
// 헤더가 **없어야** 한다.
const LIST = ['http://localhost:3000', 'http://localhost:8080'];

Deno.test('matchOrigin: 허용 목록의 오리진은 그대로 되돌려준다', () => {
  assertEquals(matchOrigin('http://localhost:3000', LIST), 'http://localhost:3000');
  assertEquals(matchOrigin('http://localhost:8080', LIST), 'http://localhost:8080');
});

Deno.test('matchOrigin: 목록 밖 오리진은 null (헤더를 붙이지 않는다)', () => {
  assertEquals(matchOrigin('https://evil.example', LIST), null);
  // 부분 일치·포트 누락으로 통과하지 않는다.
  assertEquals(matchOrigin('http://localhost', LIST), null);
  assertEquals(matchOrigin('http://localhost:3000.evil.example', LIST), null);
});

Deno.test('matchOrigin: Origin 없는 호출(모바일·서버)은 null', () => {
  assertEquals(matchOrigin(null, LIST), null);
});

Deno.test('matchOrigin: 목록이 비었거나 *면 모두 허용(로컬 개발 폴백)', () => {
  assertEquals(matchOrigin('https://anything.example', []), 'https://anything.example');
  assertEquals(matchOrigin('https://anything.example', ['*']), 'https://anything.example');
  assertEquals(matchOrigin(null, []), '*');
});

Deno.test('withCors: 핸들러 응답에 Vary: Origin 을 붙이고 상태·본문을 보존한다', async () => {
  const handler = withCors(() => jsonResponse({ ok: true }, { status: 201 }));
  const res = await handler(new Request('https://x', { headers: { Origin: 'https://a.example' } }));
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { ok: true });
  assert(res.headers.get('Vary')?.includes('Origin'));
});
