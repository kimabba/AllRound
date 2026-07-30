import { assertAlmostEquals, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { boundingBox, distanceKm, numberParam } from '../clubs-search/nearby.ts';

Deno.test('nearby club distance is zero for the same coordinates', () => {
  assertEquals(distanceKm(37.5665, 126.978, 37.5665, 126.978), 0);
});

Deno.test('nearby club distance calculates a realistic Seoul distance', () => {
  const distance = distanceKm(37.5665, 126.978, 37.5512, 126.9882);
  assertAlmostEquals(distance, 1.92, 0.1);
});

Deno.test('bounding box covers every point within the radius', () => {
  const latitude = 37.5665;
  const longitude = 126.978;
  const radiusKm = 10;
  const box = boundingBox(latitude, longitude, radiusKm);

  // 정북·정동으로 반경만큼 간 점은 사각형 안에 있어야 한다(잘리면 근거리 클럽이 누락된다).
  const north = latitude + radiusKm / 111.32;
  const east = longitude +
    radiusKm / (111.32 * Math.cos(latitude * Math.PI / 180));
  assertEquals(north <= box.maxLatitude, true);
  assertEquals(east <= box.maxLongitude, true);
  // 반경 밖(2배 거리)은 사각형 밖이어야 한다.
  assertEquals(latitude + 2 * radiusKm / 111.32 > box.maxLatitude, true);
});

Deno.test('nearby number parameters reject missing and invalid numbers', () => {
  assertEquals(numberParam(null), null);
  assertEquals(numberParam(''), null);
  assertEquals(numberParam('invalid'), null);
  assertEquals(numberParam('5'), 5);
});
