import { assertAlmostEquals, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { distanceKm, numberParam } from '../clubs-search/nearby.ts';

Deno.test('nearby club distance is zero for the same coordinates', () => {
  assertEquals(distanceKm(37.5665, 126.978, 37.5665, 126.978), 0);
});

Deno.test('nearby club distance calculates a realistic Seoul distance', () => {
  const distance = distanceKm(37.5665, 126.978, 37.5512, 126.9882);
  assertAlmostEquals(distance, 1.92, 0.1);
});

Deno.test('nearby number parameters reject missing and invalid numbers', () => {
  assertEquals(numberParam(null), null);
  assertEquals(numberParam(''), null);
  assertEquals(numberParam('invalid'), null);
  assertEquals(numberParam('5'), 5);
});
