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

Deno.test('FCM payload fills optional fields with empty strings', () => {
  const payload = buildFcmPayload(['token-1'], {
    userId: 'user-1',
    type: 'club_notice',
    title: '공지',
    body: null,
  });

  if (payload.notification.body !== '') {
    throw new Error('null body must become empty string');
  }
  if (
    payload.data.reference_type !== '' ||
    payload.data.reference_id !== '' ||
    payload.data.club_id !== ''
  ) {
    throw new Error('missing metadata must become empty strings');
  }
  if (payload.priority !== 'high') {
    throw new Error('priority must be high');
  }
});

Deno.test('FCM payload trims whitespace-only body to empty string', () => {
  const payload = buildFcmPayload(['token-1'], {
    userId: 'user-1',
    type: 'club_notice',
    title: '공지',
    body: '   ',
  });

  if (payload.notification.body !== '') {
    throw new Error('whitespace-only body must become empty string');
  }
});

Deno.test('FCM payload passes title through without trimming', () => {
  const payload = buildFcmPayload(['token-1'], {
    userId: 'user-1',
    type: 'club_notice',
    title: ' 공지 ',
  });

  if (payload.notification.title !== ' 공지 ') {
    throw new Error('title must be passed through verbatim');
  }
});

Deno.test('FCM payload keeps the token list as registration_ids', () => {
  const payload = buildFcmPayload(['token-1', 'token-2'], {
    userId: 'user-1',
    type: 'club_notice',
    title: '공지',
  });

  if (
    payload.registration_ids.length !== 2 ||
    payload.registration_ids[0] !== 'token-1' ||
    payload.registration_ids[1] !== 'token-2'
  ) {
    throw new Error('registration_ids must mirror the token list');
  }
});
