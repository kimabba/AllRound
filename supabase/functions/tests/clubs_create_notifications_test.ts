import { assertEquals } from 'std/assert/mod.ts';

import { selectNotificationTargets } from '../_shared/notifications.ts';
import {
  adminIdsFromRows,
  buildClubApprovalNotification,
  buildClubRejectionNotification,
} from '../clubs-create/notifications.ts';

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
      title: '새 클럽 승인 요청',
      body: '“주말 푸살 클럽” 클럽이 승인을 기다리고 있습니다.',
      referenceType: 'club_approval_request',
      referenceId: 'club-1',
      clubId: 'club-1',
      delivery: 'latest_device',
    },
  );
});

Deno.test('club resubmission tells administrators that the club was edited', () => {
  const notification = buildClubApprovalNotification(
    'admin-1',
    { clubId: 'club-1', clubName: '주말 풋살 클럽' },
    'resubmission',
  );
  assertEquals(notification.title, '클럽 재검수 요청');
  assertEquals(notification.body, '“주말 풋살 클럽” 클럽이 수정 후 재검수를 요청했습니다.');
});

Deno.test('club rejection notification includes the administrator reason', () => {
  assertEquals(
    buildClubRejectionNotification({
      clubId: 'club-1',
      clubName: '주말 풋살 클럽',
      ownerId: 'owner-1',
      reason: '활동 장소를 더 정확히 입력해주세요.',
    }),
    {
      userId: 'owner-1',
      type: 'club_creation_rejected',
      title: '클럽 생성 요청이 거절되었습니다',
      body: '“주말 풋살 클럽” 거절 사유: 활동 장소를 더 정확히 입력해주세요.',
      referenceType: 'club_creation_review',
      referenceId: 'club-1',
      clubId: 'club-1',
      delivery: 'latest_device',
    },
  );
});
