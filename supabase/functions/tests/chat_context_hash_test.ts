import { assertEquals, assertNotEquals } from 'std/assert/mod.ts';
import { computeUserContextHash, gradeLabelOf } from '../chat/context.ts';
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

// ─── gradeLabelOf (#319) ─────────────────────────────────────
// 등급 라벨 정본은 DB grades.label_ko 고, chat 은 user_sports 조회에 임베드해 받는다.
// PostgREST 가 복합 FK 를 to-one 으로 좁히면 객체, 아니면 배열로 오므로 둘 다 받아야 한다.

Deno.test('gradeLabelOf reads the embedded DB label (object form)', () => {
  assertEquals(
    gradeLabelOf({
      sport: 'futsal',
      grade: 'intro',
      is_primary: true,
      grades: { label_ko: '입문' },
    }),
    '입문',
  );
});

Deno.test('gradeLabelOf reads the embedded DB label (array form)', () => {
  assertEquals(
    gradeLabelOf({
      sport: 'futsal',
      grade: 'intro',
      is_primary: true,
      grades: [{ label_ko: '입문' }],
    }),
    '입문',
  );
});

Deno.test('gradeLabelOf falls back to the code when the embed is missing', () => {
  assertEquals(gradeLabelOf({ sport: 'tennis', grade: 'y1to3', is_primary: true }), 'y1to3');
  assertEquals(
    gradeLabelOf({ sport: 'tennis', grade: 'y1to3', is_primary: true, grades: null }),
    'y1to3',
  );
  // 임베드가 빈 배열로 와도(조인 0행) 코드로 떨어진다 — 라벨 사본을 두지 않는다.
  assertEquals(
    gradeLabelOf({ sport: 'tennis', grade: 'y1to3', is_primary: true, grades: [] }),
    'y1to3',
  );
});
