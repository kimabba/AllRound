import { assert, assertEquals } from 'std/assert/mod.ts';
import { buildTournamentSelect } from '../embed-pending/index.ts';

Deno.test('선별: pending/processing 제외 + revision 컬럼 포함', () => {
  const spec = buildTournamentSelect();
  assert(spec.columns.includes('embedding_input_revision'));
  assertEquals(spec.excludeFormatStatus, ['pending', 'processing']);
  assertEquals(spec.onlyStatus, 'published');
});
