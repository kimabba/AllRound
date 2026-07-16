import { assertEquals } from 'std/assert/mod.ts';
import { penaltyTypesForAction } from '../_shared/ugc.ts';

Deno.test('club join checks both join and community restrictions', () => {
  assertEquals(penaltyTypesForAction('club_join'), [
    'club_join_restriction',
    'community_restriction',
  ]);
});

Deno.test('community creation checks the broad restriction', () => {
  assertEquals(penaltyTypesForAction('community_create'), [
    'community_restriction',
  ]);
});
