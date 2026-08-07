import { assertEquals } from 'std/assert/mod.ts';

import { selectNotificationTargets } from '../_shared/notifications.ts';
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

Deno.test('club approval push uses only the newest administrator device', () => {
  const devices = [
    { token: 'newest', platform: 'ios' as const, sound_enabled: true },
    { token: 'old-1', platform: 'ios' as const, sound_enabled: true },
    { token: 'old-2', platform: 'ios' as const, sound_enabled: true },
  ];

  assertEquals(selectNotificationTargets(devices, 'latest_device'), [devices[0]]);
  assertEquals(selectNotificationTargets(devices, 'all_devices'), devices);
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
      title: '새 모임 승인 요청',
      body: '“주말 푸살 클럽” 모임이 승인을 기다리고 있습니다.',
      referenceType: 'club_approval_request',
      referenceId: 'club-1',
      clubId: 'club-1',
      delivery: 'latest_device',
    },
  );
});
