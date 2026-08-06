import { assertEquals } from 'std/assert/mod.ts';

import { rejoiningUserIdsFromRows } from '../clubs-review-join/request_history.ts';

Deno.test('only members who left by themselves are marked as rejoining', () => {
  assertEquals(
    [...rejoiningUserIdsFromRows([
      { user_id: 'left-user', status: 'left' },
      { user_id: 'active-user', status: 'active' },
      { user_id: '', status: 'left' },
      null,
    ])],
    ['left-user'],
  );
});
