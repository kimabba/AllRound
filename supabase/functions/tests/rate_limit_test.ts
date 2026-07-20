import { assert, assertEquals } from 'std/assert/mod.ts';
import { SupabaseClient } from '@supabase/supabase-js';

import { checkRateLimit } from '../_shared/rate_limit.ts';

// consume_rate_limit RPC만 흉내내는 최소 fake 클라이언트.
function fakeClient(result: { data: unknown; error: unknown }): SupabaseClient {
  return { rpc: () => Promise.resolve(result) } as unknown as SupabaseClient;
}

const cfg = { bucket: 'chat', maxPerWindow: 30, windowSeconds: 60 };

Deno.test('rate_limit fail-open: RPC 에러 시 요청 통과(null)', async () => {
  const client = fakeClient({ data: null, error: { message: 'db down' } });
  assertEquals(await checkRateLimit(client, 'u1', cfg), null);
});

Deno.test('rate_limit allowed: allowed=true면 통과(null)', async () => {
  const client = fakeClient({
    data: { allowed: true, current_count: 1, reset_at: new Date().toISOString() },
    error: null,
  });
  assertEquals(await checkRateLimit(client, 'u1', cfg), null);
});

Deno.test('rate_limit allowed: data가 배열이어도 첫 행으로 판정', async () => {
  const client = fakeClient({
    data: [{ allowed: true, current_count: 1, reset_at: new Date().toISOString() }],
    error: null,
  });
  assertEquals(await checkRateLimit(client, 'u1', cfg), null);
});

Deno.test('rate_limit denied: 429 + Retry-After + 본문 메타', async () => {
  const resetAt = new Date(Date.now() + 60_000).toISOString();
  const client = fakeClient({
    data: { allowed: false, current_count: 31, reset_at: resetAt },
    error: null,
  });
  const res = await checkRateLimit(client, 'u1', cfg);
  assert(res instanceof Response);
  assertEquals(res!.status, 429);
  const retry = Number(res!.headers.get('Retry-After'));
  assert(retry >= 1 && retry <= 61, `Retry-After 범위 밖: ${retry}`);
  const body = await res!.json();
  assertEquals(body.limit, 30);
  assertEquals(body.window_seconds, 60);
  assertEquals(body.reset_at, resetAt);
  assert(String(body.error).includes('chat'));
});

Deno.test('rate_limit denied: reset_at 과거면 Retry-After 최소 1', async () => {
  const resetAt = new Date(Date.now() - 5_000).toISOString();
  const client = fakeClient({
    data: { allowed: false, current_count: 99, reset_at: resetAt },
    error: null,
  });
  const res = await checkRateLimit(client, 'u1', cfg);
  assert(res instanceof Response);
  assertEquals(res!.headers.get('Retry-After'), '1');
});
