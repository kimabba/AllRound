import { assert, assertEquals } from 'std/assert/mod.ts';
import type { SupabaseClient } from '@supabase/supabase-js';
import { buildTournamentSelect, runTournamentEmbedding } from '../embed-pending/index.ts';

interface FakeTournamentRow {
  id: string;
  title: string;
  description: string | null;
  region: string | null;
  format: string | null;
  organizer: string | null;
  regulation_fields: unknown;
  regulation_body: string | null;
  embedding_input_revision: number;
}

/**
 * runTournamentEmbedding 이 호출하는 체인만 구현한 최소 fake.
 *   - from('tournaments').select(...).is().eq().not().limit() → pending rows
 *   - from('tournaments').update(payload).eq('id',..).eq('embedding_input_revision',..).select('id')
 *     → onEq 로 각 .eq() 호출을 캡처, opts.updateReturnsRows 로 반환 행 수 제어(기본 1행 = 성공)
 */
function makeEmbedFakeClient(
  rows: FakeTournamentRow[],
  onEq: (col: string, val: unknown) => void,
  opts: { updateReturnsRows?: number } = {},
): SupabaseClient {
  const fake = {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        is: (_c: string, _v: unknown) => ({
          eq: (_c2: string, _v2: unknown) => ({
            not: (_c3: string, _op: string, _v3: unknown) => ({
              limit: (_n: number) => Promise.resolve({ data: rows, error: null }),
            }),
          }),
        }),
      }),
      update: (_payload: Record<string, unknown>) => ({
        eq: (col: string, val: unknown) => {
          onEq(col, val);
          return {
            eq: (col2: string, val2: unknown) => {
              onEq(col2, val2);
              return {
                select: (_cols: string) => {
                  const n = opts.updateReturnsRows ?? 1;
                  const data = n === 0 ? [] : [{ id: rows[0]?.id }];
                  return Promise.resolve({ data, error: null });
                },
              };
            },
          };
        },
      }),
    }),
  };
  return fake as unknown as SupabaseClient;
}

Deno.test('선별: pending/processing 제외 + revision 컬럼 포함', () => {
  const spec = buildTournamentSelect();
  assert(spec.columns.includes('embedding_input_revision'));
  assertEquals(spec.excludeFormatStatus, ['pending', 'processing']);
  assertEquals(spec.onlyStatus, 'published');
});

Deno.test('update: 읽은 revision과 일치 조건으로만 임베딩 저장', async () => {
  const eqCalls: Array<[string, unknown]> = [];
  const fakeClient = makeEmbedFakeClient(
    [
      {
        id: 't1',
        title: '대회',
        description: null,
        region: null,
        format: null,
        organizer: null,
        regulation_fields: null,
        regulation_body: null,
        embedding_input_revision: 7,
      },
    ],
    (col, val) => eqCalls.push([col, val]),
  );
  await runTournamentEmbedding(fakeClient, () => Promise.resolve([[0.1, 0.2]]));
  assert(eqCalls.some(([c, v]) => c === 'id' && v === 't1'));
  assert(eqCalls.some(([c, v]) => c === 'embedding_input_revision' && v === 7));
});

Deno.test('경합: update가 0행이면 skipped 처리(덮어쓰지 않음)', async () => {
  const client = makeEmbedFakeClient(
    [
      {
        id: 't1',
        title: '대회',
        description: null,
        region: null,
        format: null,
        organizer: null,
        regulation_fields: null,
        regulation_body: null,
        embedding_input_revision: 7,
      },
    ],
    () => {},
    { updateReturnsRows: 0 },
  );
  const r = await runTournamentEmbedding(client, () => Promise.resolve([[0.1]]));
  assertEquals(r.skipped, 1);
  assertEquals(r.processed, 0);
});
