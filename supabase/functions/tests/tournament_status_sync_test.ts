import { assertEquals } from 'std/assert/mod.ts';
import type { SupabaseClient } from '@supabase/supabase-js';
import { syncTournamentStatus } from '../_shared/tournament_status.ts';

// JY-151: auto-close 가 단방향이라 마감 전 대회가 closed 로 굳었다. 되살리기 조건이
// 뒤집히면(gte → lt) 이미 끝난 대회가 홈에 다시 뜨므로, 필터를 실제로 캡처해 확인한다.

interface UpdateCall {
  payload: Record<string, string>;
  filters: string[];
}

function fakeClient(counts: Array<number | null>) {
  const calls: UpdateCall[] = [];
  let index = 0;
  const client = {
    from(_table: string) {
      return {
        update(payload: Record<string, string>, _options: { count: 'exact' }) {
          const call: UpdateCall = { payload, filters: [] };
          calls.push(call);
          const count = counts[index++] ?? null;
          const builder = {
            eq(column: string, value: string) {
              call.filters.push(`eq:${column}=${value}`);
              return builder;
            },
            lt(column: string, value: string) {
              call.filters.push(`lt:${column}=${value}`);
              return builder;
            },
            gte(column: string, value: string) {
              call.filters.push(`gte:${column}=${value}`);
              return builder;
            },
            then(resolve: (result: { count: number | null; error: null }) => unknown) {
              return Promise.resolve(resolve({ count, error: null }));
            },
          };
          return builder;
        },
      };
    },
  };
  return { client: client as unknown as SupabaseClient, calls };
}

Deno.test('지난 대회는 closed 로, 다시 미래가 된 closed 는 published 로 되돌린다', async () => {
  const { client, calls } = fakeClient([2, 3]);

  const result = await syncTournamentStatus(client, '2026-08-01');

  assertEquals(result, { closed: 2, reopened: 3 });
  assertEquals(calls.length, 2);
  assertEquals(calls[0].payload, { status: 'closed' });
  assertEquals(calls[0].filters, ['eq:status=published', 'lt:start_date=2026-08-01']);
  assertEquals(calls[1].payload, { status: 'published' });
  // gte: 오늘 시작하는 대회는 아직 열려 있어야 한다(경계 포함).
  assertEquals(calls[1].filters, ['eq:status=closed', 'gte:start_date=2026-08-01']);
});

Deno.test('count 가 없으면 0 으로 보고한다', async () => {
  const { client } = fakeClient([null, null]);
  assertEquals(await syncTournamentStatus(client, '2026-08-01'), { closed: 0, reopened: 0 });
});
