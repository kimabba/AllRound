import { assertEquals, assertMatch } from 'std/assert/mod.ts';
import type { SupabaseClient } from '@supabase/supabase-js';
import { syncTournamentStatus } from '../_shared/tournament_status.ts';

// JY-151: auto-close 가 단방향이라 마감 전 대회가 closed 로 굳었다. 되살리기 조건이
// 뒤집히면(gte → lt) 이미 끝난 대회가 홈에 다시 뜨므로, 필터를 실제로 캡처해 확인한다.
//
// 목록이탈 만료(delisted_at) 추가 후: 되살리기가 날짜-close 만 되돌리는지(delisted_at is
// null 가드), 소스별 delist 루프가 last_listing_parsed_at 없는 소스를 건너뛰는지도 함께
// 검증한다 — backend-architect 검토에서 나온 "reopen이 delist를 되돌리면 기능이
// 무효화된다"는 지적을 회귀 없이 지키기 위함.

interface UpdateCall {
  table: string;
  payload: Record<string, unknown>;
  filters: string[];
}

interface SelectCall {
  table: string;
  filters: string[];
}

function fakeClient(opts: {
  crawlSources: Array<{ slug: string; last_listing_parsed_at: string }>;
  updateCounts: Array<number | null>; // 순서: [closed, reopened, ...소스별 delist count]
}) {
  const updateCalls: UpdateCall[] = [];
  const selectCalls: SelectCall[] = [];
  let updateIndex = 0;
  const client = {
    from(table: string) {
      if (table === 'crawl_sources') {
        return {
          select(_cols: string) {
            const call: SelectCall = { table, filters: [] };
            selectCalls.push(call);
            const builder = {
              not(column: string, op: string, value: unknown) {
                call.filters.push(`not.${op}:${column}=${value}`);
                return builder;
              },
              then(resolve: (r: { data: typeof opts.crawlSources; error: null }) => unknown) {
                return Promise.resolve(resolve({ data: opts.crawlSources, error: null }));
              },
            };
            return builder;
          },
        };
      }
      return {
        update(payload: Record<string, unknown>, _options: { count: 'exact' }) {
          const call: UpdateCall = { table, payload, filters: [] };
          updateCalls.push(call);
          const count = opts.updateCounts[updateIndex++] ?? null;
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
            is(column: string, value: unknown) {
              call.filters.push(`is:${column}=${value}`);
              return builder;
            },
            not(column: string, op: string, value: unknown) {
              call.filters.push(`not.${op}:${column}=${value}`);
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
  return { client: client as unknown as SupabaseClient, updateCalls, selectCalls };
}

Deno.test('지난 대회는 closed 로, 다시 미래가 된 closed 는 published 로 되돌린다', async () => {
  const { client, updateCalls } = fakeClient({ crawlSources: [], updateCounts: [2, 3] });

  const result = await syncTournamentStatus(client, '2026-08-01');

  assertEquals(result, { closed: 2, reopened: 3, delisted: 0 });
  assertEquals(updateCalls.length, 2);
  assertEquals(updateCalls[0].payload, { status: 'closed' });
  assertEquals(updateCalls[0].filters, ['eq:status=published', 'lt:start_date=2026-08-01']);
  assertEquals(updateCalls[1].payload, { status: 'published' });
  // gte: 오늘 시작하는 대회는 아직 열려 있어야 한다(경계 포함).
  assertEquals(updateCalls[1].filters, [
    'eq:status=closed',
    'is:delisted_at=null',
    'gte:start_date=2026-08-01',
  ]);
});

Deno.test('count 가 없으면 0 으로 보고한다', async () => {
  const { client } = fakeClient({ crawlSources: [], updateCounts: [null, null] });
  assertEquals(await syncTournamentStatus(client, '2026-08-01'), {
    closed: 0,
    reopened: 0,
    delisted: 0,
  });
});

Deno.test('되살리기는 delisted_at 이 null 인 행만 대상으로 한다(목록이탈-close 는 안 건드림)', async () => {
  const { client, updateCalls } = fakeClient({ crawlSources: [], updateCounts: [0, 0] });
  await syncTournamentStatus(client, '2026-08-01');
  const reopenCall = updateCalls[1];
  assertEquals(reopenCall.payload, { status: 'published' });
  // 이 가드가 없으면 목록이탈로 닫힌 대회가 start_date 만 보고 매 run 마다 되살아나
  // 기능이 무효화된다(backend-architect 지적).
  assertEquals(reopenCall.filters.includes('is:delisted_at=null'), true);
});

Deno.test('목록이탈 만료: last_listing_parsed_at 있는 소스만 대상, 소스별로 닫히고 delisted_at 이 찍힌다', async () => {
  const { client, updateCalls, selectCalls } = fakeClient({
    crawlSources: [
      { slug: 'gj', last_listing_parsed_at: '2026-08-10T00:00:00.000Z' },
      { slug: 'jn', last_listing_parsed_at: '2026-08-11T00:00:00.000Z' },
    ],
    updateCounts: [0, 0, 2, 1], // closed, reopened, gj delist, jn delist
  });

  const result = await syncTournamentStatus(client, '2026-08-15');

  assertEquals(result.delisted, 3); // 2 + 1
  assertEquals(selectCalls.length, 1);
  assertEquals(selectCalls[0].table, 'crawl_sources');
  assertEquals(selectCalls[0].filters, ['not.is:last_listing_parsed_at=null']);

  const delistCalls = updateCalls.slice(2);
  assertEquals(delistCalls.length, 2);
  for (const [i, slug] of ['gj', 'jn'].entries()) {
    const call = delistCalls[i];
    assertEquals(call.table, 'tournaments');
    assertEquals(call.payload.status, 'closed');
    assertEquals(typeof call.payload.delisted_at, 'string');
    assertEquals(call.filters[0], 'eq:status=published');
    assertEquals(call.filters[1], `eq:source=${slug}`);
    assertEquals(call.filters[2], 'not.is:last_seen_at=null');
    // cutoff(7일 전, 실행 시각 기준)는 값을 고정할 수 없으니 ISO 형식인지만 확인.
    assertMatch(call.filters[3], /^lt:last_seen_at=\d{4}-\d{2}-\d{2}T/);
    // last_listing_parsed_at 상한은 소스별 값 그대로.
    assertEquals(
      call.filters[4],
      `lt:last_seen_at=${['2026-08-10T00:00:00.000Z', '2026-08-11T00:00:00.000Z'][i]}`,
    );
  }
});

Deno.test('목록이탈 만료: last_listing_parsed_at 없는(=한 번도 전체 파싱 안 된) 소스는 없음', async () => {
  const { client, updateCalls } = fakeClient({ crawlSources: [], updateCounts: [0, 0] });
  const result = await syncTournamentStatus(client, '2026-08-15');
  assertEquals(result.delisted, 0);
  assertEquals(updateCalls.length, 2); // closed, reopened 뿐 — delist 루프는 안 돔
});
