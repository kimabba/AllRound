export interface FcmNotificationInput {
  title: string;
  body?: string | null;
  type: string;
  referenceType?: string | null;
  referenceId?: string | null;
  clubId?: string | null;
}

export interface FcmTarget {
  token: string;
  soundEnabled: boolean;
}

export interface FcmBatchResult {
  status: 'sent' | 'failed' | 'skipped';
  sentCount: number;
  failedCount: number;
  error: string | null;
}

interface FirebaseCredentials {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

interface CachedAccessToken {
  value: string;
  expiresAtMs: number;
  credentialKey: string;
}

type Fetcher = typeof fetch;

const messagingScope = 'https://www.googleapis.com/auth/firebase.messaging';
const tokenAudience = 'https://oauth2.googleapis.com/token';
let cachedAccessToken: CachedAccessToken | null = null;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToPkcs8(privateKey: string): ArrayBuffer {
  const normalized = privateKey.replaceAll('\\n', '\n');
  const privateKeyLabel = 'PRIVATE' + ' KEY';
  const base64 = normalized
    .replace(`-----BEGIN ${privateKeyLabel}-----`, '')
    .replace(`-----END ${privateKeyLabel}-----`, '')
    .replaceAll(/\s/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

export function parseFirebaseCredentials(raw: string | undefined): FirebaseCredentials | null {
  if (!raw) return null;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!isRecord(parsed)) return null;
    const projectId = parsed['project_id'];
    const clientEmail = parsed['client_email'];
    const privateKey = parsed['private_key'];
    if (
      typeof projectId !== 'string' || projectId.trim().length === 0 ||
      typeof clientEmail !== 'string' || clientEmail.trim().length === 0 ||
      typeof privateKey !== 'string' || privateKey.trim().length === 0
    ) {
      return null;
    }
    return {
      projectId: projectId.trim(),
      clientEmail: clientEmail.trim(),
      privateKey,
    };
  } catch {
    return null;
  }
}

export function buildFcmPayload(target: FcmTarget, input: FcmNotificationInput) {
  const aps = target.soundEnabled ? { sound: 'default' } : {};
  return {
    message: {
      token: target.token,
      notification: {
        title: input.title,
        body: input.body?.trim() ?? '',
      },
      data: {
        type: input.type,
        reference_type: input.referenceType ?? '',
        reference_id: input.referenceId ?? '',
        club_id: input.clubId ?? '',
      },
      android: { priority: 'HIGH' },
      apns: { payload: { aps } },
    },
  };
}

async function createSignedAssertion(credentials: FirebaseCredentials, nowSeconds: number) {
  const header = encodeJson({ alg: 'RS256', typ: 'JWT' });
  const claims = encodeJson({
    iss: credentials.clientEmail,
    scope: messagingScope,
    aud: tokenAudience,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  });
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(credentials.privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

async function getAccessToken(
  credentials: FirebaseCredentials,
  fetcher: Fetcher,
): Promise<string> {
  const nowMs = Date.now();
  const credentialKey = `${credentials.projectId}:${credentials.clientEmail}`;
  if (
    cachedAccessToken && cachedAccessToken.credentialKey === credentialKey &&
    cachedAccessToken.expiresAtMs > nowMs + 60_000
  ) {
    return cachedAccessToken.value;
  }

  const assertion = await createSignedAssertion(credentials, Math.floor(nowMs / 1000));
  const response = await fetcher(tokenAudience, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const payload: unknown = await response.json();
  if (!response.ok || !isRecord(payload) || typeof payload['access_token'] !== 'string') {
    throw new Error(`firebase_oauth_failed:${response.status}`);
  }
  const expiresIn = typeof payload['expires_in'] === 'number' ? payload['expires_in'] : 3600;
  cachedAccessToken = {
    value: payload['access_token'],
    expiresAtMs: nowMs + expiresIn * 1000,
    credentialKey,
  };
  return cachedAccessToken.value;
}

export async function sendFcm(
  targets: FcmTarget[],
  input: FcmNotificationInput,
  options: {
    serviceAccountJson?: string;
    fetcher?: Fetcher;
  } = {},
): Promise<FcmBatchResult> {
  const uniqueTargets = [
    ...new Map(
      targets
        .map((target) => ({ ...target, token: target.token.trim() }))
        .filter((target) => target.token.length > 0)
        .map((target) => [target.token, target]),
    ).values(),
  ];
  if (uniqueTargets.length === 0) {
    return { status: 'skipped', sentCount: 0, failedCount: 0, error: 'no_device_tokens' };
  }

  const credentials = parseFirebaseCredentials(
    options.serviceAccountJson ?? Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON'),
  );
  if (!credentials) {
    return {
      status: 'failed',
      sentCount: 0,
      failedCount: uniqueTargets.length,
      error: 'firebase_credentials_missing_or_invalid',
    };
  }

  const fetcher = options.fetcher ?? fetch;
  try {
    const accessToken = await getAccessToken(credentials, fetcher);
    const results = await Promise.all(uniqueTargets.map(async (target) => {
      const response = await fetcher(
        `https://fcm.googleapis.com/v1/projects/${
          encodeURIComponent(credentials.projectId)
        }/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(buildFcmPayload(target, input)),
        },
      );
      return response.ok;
    }));
    const sentCount = results.filter((sent) => sent).length;
    const failedCount = results.length - sentCount;
    return {
      status: failedCount === 0 ? 'sent' : 'failed',
      sentCount,
      failedCount,
      error: failedCount === 0 ? null : `fcm_partial_or_total_failure:${failedCount}`,
    };
  } catch (error) {
    return {
      status: 'failed',
      sentCount: 0,
      failedCount: uniqueTargets.length,
      error: error instanceof Error ? error.message : 'fcm_unknown_error',
    };
  }
}
