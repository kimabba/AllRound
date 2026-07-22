import { buildFcmPayload } from '../_shared/notifications.ts';

Deno.test('FCM payload carries notification deep-link metadata', () => {
  const payload = buildFcmPayload(['token-1'], {
    userId: 'user-1',
    type: 'club_join_request',
    title: '새 클럽 가입 신청',
    body: ' 신청이 도착했습니다. ',
    referenceType: 'club_join_request',
    referenceId: 'request-1',
    clubId: 'club-1',
  });

  if (payload.notification.body !== '신청이 도착했습니다.') {
    throw new Error('notification body must be trimmed');
  }
  if (
    payload.data.reference_type !== 'club_join_request' ||
    payload.data.reference_id !== 'request-1' ||
    payload.data.club_id !== 'club-1'
  ) {
    throw new Error('deep-link metadata is missing');
  }
});
