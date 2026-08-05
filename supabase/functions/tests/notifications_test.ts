import { buildFcmPayload, parseFirebaseCredentials, sendFcm } from '../_shared/fcm.ts';

Deno.test('FCM payload carries notification deep-link metadata', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_join_request',
    title: '새 클럽 가입 신청',
    body: ' 신청이 도착했습니다. ',
    referenceType: 'club_join_request',
    referenceId: 'request-1',
    clubId: 'club-1',
  });

  if (payload.message.notification.body !== '신청이 도착했습니다.') {
    throw new Error('notification body must be trimmed');
  }
  if (
    payload.message.data.reference_type !== 'club_join_request' ||
    payload.message.data.reference_id !== 'request-1' ||
    payload.message.data.club_id !== 'club-1'
  ) {
    throw new Error('deep-link metadata is missing');
  }
});

Deno.test('FCM payload fills optional fields with empty strings', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_notice',
    title: '공지',
    body: null,
  });

  if (payload.message.notification.body !== '') {
    throw new Error('null body must become empty string');
  }
  if (
    payload.message.data.reference_type !== '' ||
    payload.message.data.reference_id !== '' ||
    payload.message.data.club_id !== ''
  ) {
    throw new Error('missing metadata must become empty strings');
  }
  if (payload.message.android.priority !== 'HIGH') {
    throw new Error('Android priority must be HIGH');
  }
});

Deno.test('FCM payload trims whitespace-only body to empty string', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_notice',
    title: '공지',
    body: '   ',
  });

  if (payload.message.notification.body !== '') {
    throw new Error('whitespace-only body must become empty string');
  }
});

Deno.test('FCM payload passes title through without trimming', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_notice',
    title: ' 공지 ',
  });

  if (payload.message.notification.title !== ' 공지 ') {
    throw new Error('title must be passed through verbatim');
  }
});

Deno.test('FCM HTTP v1 payload targets one device token', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_notice',
    title: '공지',
  });

  if (
    payload.message.token !== 'token-1'
  ) {
    throw new Error('message token must target exactly one device');
  }
});

Deno.test('FCM payload omits APNs sound when the device disabled notification sound', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: false }, {
    type: 'club_notice',
    title: '공지',
  });

  if ('sound' in payload.message.apns.payload.aps) {
    throw new Error('silent devices must not receive an APNs sound value');
  }
});

Deno.test('FCM payload uses the default APNs sound when enabled', () => {
  const payload = buildFcmPayload({ token: 'token-1', soundEnabled: true }, {
    type: 'club_notice',
    title: '공지',
  });

  if (payload.message.apns.payload.aps.sound !== 'default') {
    throw new Error('audible devices must receive the default APNs sound');
  }
});

Deno.test('Firebase credentials reject missing required fields', () => {
  if (parseFirebaseCredentials('{"project_id":"project"}') !== null) {
    throw new Error('incomplete credentials must be rejected');
  }
});

Deno.test('FCM send skips accurately when a user has no device token', async () => {
  const result = await sendFcm([], {
    type: 'club_notice',
    title: '공지',
  }, { serviceAccountJson: '{}' });
  if (result.status !== 'skipped' || result.error !== 'no_device_tokens') {
    throw new Error('missing tokens must be recorded as skipped');
  }
});

Deno.test('FCM send fails accurately when credentials are missing', async () => {
  const result = await sendFcm([{ token: 'token-1', soundEnabled: true }], {
    type: 'club_notice',
    title: '공지',
  }, { serviceAccountJson: '{}' });
  if (result.status !== 'failed' || result.error !== 'firebase_credentials_missing_or_invalid') {
    throw new Error('missing credentials must not be recorded as sent');
  }
});

Deno.test('FCM send exchanges OAuth token and calls the HTTP v1 endpoint', async () => {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', keyPair.privateKey));
  let binary = '';
  for (const byte of pkcs8) binary += String.fromCharCode(byte);
  const privateKeyLabel = 'PRIVATE' + ' KEY';
  const serviceAccountJson = JSON.stringify({
    project_id: 'allround-test',
    client_email: 'fcm-test@allround-test.iam.gserviceaccount.com',
    private_key: `-----BEGIN ${privateKeyLabel}-----\n${
      btoa(binary)
    }\n-----END ${privateKeyLabel}-----\n`,
  });
  const requestedUrls: string[] = [];
  const fakeFetch: typeof fetch = (input) => {
    const url = input instanceof Request ? input.url : input.toString();
    requestedUrls.push(url);
    if (url === 'https://oauth2.googleapis.com/token') {
      return Promise.resolve(
        Response.json({ access_token: 'test-access-token', expires_in: 3600 }),
      );
    }
    return Promise.resolve(Response.json({ name: 'projects/allround-test/messages/1' }));
  };

  const result = await sendFcm([{ token: 'token-1', soundEnabled: true }], {
    type: 'club_notice',
    title: '공지',
  }, { serviceAccountJson, fetcher: fakeFetch });

  if (result.status !== 'sent' || result.sentCount !== 1 || result.failedCount !== 0) {
    throw new Error('successful HTTP v1 delivery must be recorded as sent');
  }
  if (
    requestedUrls[0] !== 'https://oauth2.googleapis.com/token' ||
    requestedUrls[1] !==
      'https://fcm.googleapis.com/v1/projects/allround-test/messages:send'
  ) {
    throw new Error(`unexpected FCM HTTP v1 request sequence: ${requestedUrls.join(',')}`);
  }
});
