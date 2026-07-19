import { assertEquals, assertNotEquals } from 'std/assert/mod.ts';
import { computeUserContextHash } from '../chat/context.ts';
import type { UserSport, UserTennisOrgRow } from '../chat/types.ts';

const sports: UserSport[] = [
  { sport: 'tennis', grade: 'beginner', is_primary: true },
];
const orgs: UserTennisOrgRow[] = [
  {
    org: 'kato',
    division: 'rookie',
    division_codes: ['ROOKIE'],
    score: 10,
    is_primary: true,
    region_code: 'seoul',
  },
];

Deno.test('semantic cache hash isolates users with identical profiles', async () => {
  const userAHash = await computeUserContextHash('user-a', sports, orgs);
  const userBHash = await computeUserContextHash('user-b', sports, orgs);

  assertNotEquals(userAHash, userBHash);
});

Deno.test('semantic cache hash is stable across source ordering', async () => {
  const first = await computeUserContextHash('user-a', sports, orgs);
  const second = await computeUserContextHash(
    'user-a',
    [...sports].reverse(),
    [...orgs].reverse(),
  );

  assertEquals(first, second);
});
