import { assertEquals } from 'std/assert/mod.ts';

import { adminIdsFromRows, buildClubApprovalNotification } from '../clubs-create/notifications.ts';

Deno.test('clubs-create extracts unique valid administrator ids', () => {
  assertEquals(
    adminIdsFromRows([
      { id: 'admin-1' },
      { id: 'admin-1' },
      { id: 'admin-2' },
      { id: '' },
      { name: 'missing-id' },
      null,
    ]),
    ['admin-1', 'admin-2'],
  );
  assertEquals(adminIdsFromRows({ id: 'not-an-array' }), []);
});

Deno.test('clubs-create builds a deduplicated admin approval notification', () => {
  assertEquals(
    buildClubApprovalNotification('admin-1', {
      clubId: 'club-1',
      clubName: '주말 푸살 클럽',
    }),
    {
      userId: 'admin-1',
      type: 'club_approval_request',
      title: '새 클럽 승인 요청',
      body: '“주말 푸살 클럽” 클럽이 승인을 기다리고 있습니다.',
      referenceType: 'club_approval_request',
      referenceId: 'club-1',
      clubId: 'club-1',
    },
  );
});
