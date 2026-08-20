import { assertEquals } from 'std/assert/mod.ts';

import { visibleMyClubRows } from '../clubs-search/mine.ts';

Deno.test('my clubs hides clubs soft-deleted by their owner', () => {
  const visible = visibleMyClubRows([
    { id: 'approved', status: 'approved', status_reason: null },
    { id: 'rejected', status: 'rejected', status_reason: '정보 부족' },
    {
      id: 'deleted',
      status: 'rejected',
      status_reason: 'deleted_by_owner',
    },
  ]);

  assertEquals(visible.map((club) => club['id']), ['approved', 'rejected']);
});
