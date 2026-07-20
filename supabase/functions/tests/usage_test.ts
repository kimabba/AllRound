import { assert, assertEquals } from 'std/assert/mod.ts';
import { SupabaseClient } from '@supabase/supabase-js';

import { recordGeminiUsage } from '../_shared/usage.ts';

// gemini_usage insert만 흉내내는 fake. 마지막 insert 인자를 캡처한다.
function fakeClient(opts: { error?: unknown; throwOn?: boolean } = {}): {
  client: SupabaseClient;
  captured: () => { table: string; row: Record<string, unknown> } | null;
} {
  let captured: { table: string; row: Record<string, unknown> } | null = null;
  const client = {
    from(table: string) {
      return {
        insert(row: Record<string, unknown>) {
          if (opts.throwOn) throw new Error('insert boom');
          captured = { table, row };
          return Promise.resolve({ error: opts.error ?? null });
        },
      };
    },
  } as unknown as SupabaseClient;
  return { client, captured: () => captured };
}

Deno.test('recordGeminiUsage: 필드를 snake_case로 매핑해 gemini_usage에 insert', async () => {
  const { client, captured } = fakeClient();
  await recordGeminiUsage(client, {
    kind: 'llm',
    model: 'gemini-x',
    inputTokens: 10,
    outputTokens: 20,
    totalTokens: 30,
    userId: 'u1',
    context: 'chat',
  });
  const c = captured();
  assert(c);
  assertEquals(c!.table, 'gemini_usage');
  assertEquals(c!.row, {
    kind: 'llm',
    model: 'gemini-x',
    input_tokens: 10,
    output_tokens: 20,
    total_tokens: 30,
    user_id: 'u1',
    context: 'chat',
  });
});

Deno.test('recordGeminiUsage: 누락 필드는 null 기본값으로 채운다', async () => {
  const { client, captured } = fakeClient();
  await recordGeminiUsage(client, { kind: 'embedding', model: 'emb' });
  assertEquals(captured()!.row, {
    kind: 'embedding',
    model: 'emb',
    input_tokens: null,
    output_tokens: null,
    total_tokens: null,
    user_id: null,
    context: null,
  });
});

Deno.test('recordGeminiUsage: insert 에러를 삼킨다(throw 안 함)', async () => {
  const { client } = fakeClient({ error: { message: 'db down' } });
  await recordGeminiUsage(client, { kind: 'llm', model: 'm' });
});

Deno.test('recordGeminiUsage: insert 예외도 삼킨다(throw 안 함)', async () => {
  const { client } = fakeClient({ throwOn: true });
  await recordGeminiUsage(client, { kind: 'llm', model: 'm' });
});
