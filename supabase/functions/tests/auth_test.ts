import { assert, assertEquals } from 'std/assert/mod.ts';
import { requireCronSecret, requireServiceRole } from '../_shared/auth.ts';

function requestWithBearer(token: string): Request {
  return new Request('https://example.test', {
    headers: { Authorization: `Bearer ${token}` },
  });
}

Deno.test('requireServiceRole rejects legacy JWT-shaped service tokens', async () => {
  Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: 'sb_secret_current' }));
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'legacy.jwt.token');
  try {
    const result = requireServiceRole(requestWithBearer('legacy.jwt.token'));
    assert('error' in result);
    assertEquals(result.error.status, 403);
    assertEquals(await result.error.json(), {
      error: 'Forbidden: Legacy service JWTs are not accepted',
    });
  } finally {
    Deno.env.delete('SUPABASE_SECRET_KEYS');
    Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
  }
});

Deno.test('requireServiceRole accepts only the configured sb_secret key', () => {
  Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: 'sb_secret_current' }));
  try {
    assert(!('error' in requireServiceRole(requestWithBearer('sb_secret_current'))));

    const wrong = requireServiceRole(requestWithBearer('sb_secret_old'));
    assert('error' in wrong);
    assertEquals(wrong.error.status, 403);
  } finally {
    Deno.env.delete('SUPABASE_SECRET_KEYS');
  }
});

Deno.test('requireCronSecret still accepts the separate internal cron secret', () => {
  Deno.env.set('INTERNAL_CRON_JWT', 'internal-random-cron-secret');
  try {
    assert(!('error' in requireCronSecret(requestWithBearer('internal-random-cron-secret'))));
  } finally {
    Deno.env.delete('INTERNAL_CRON_JWT');
  }
});
