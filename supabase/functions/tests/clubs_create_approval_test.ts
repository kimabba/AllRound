import { assertEquals } from 'std/assert/mod.ts';

import { buildAdminClubApproval } from '../clubs-create/approval.ts';

Deno.test('clubs-create keeps regular users in the approval queue', () => {
  assertEquals(
    buildAdminClubApproval(false, 'user-1', '2026-07-15T09:00:00.000Z'),
    null,
  );
});

Deno.test('clubs-create immediately approves global administrators', () => {
  assertEquals(
    buildAdminClubApproval(true, 'admin-1', '2026-07-15T09:00:00.000Z'),
    {
      status: 'approved',
      status_reason: null,
      approved_by: 'admin-1',
      approved_at: '2026-07-15T09:00:00.000Z',
    },
  );
});
