import { assertEquals } from 'std/assert/mod.ts';
import {
  ENTRY_FEE_UNITS,
  FUTSAL_GRADES,
  REGION_CODES,
  TENNIS_GRADES,
  TENNIS_ORGS,
} from '../_shared/enums.ts';

Deno.test('shared enums expose stable sport grade order', () => {
  assertEquals(TENNIS_GRADES, ['under1y', 'y1to3', 'y3to5', 'over5y']);
  assertEquals(FUTSAL_GRADES, ['beginner', 'intermediate', 'advanced']);
});

Deno.test('shared enums expose tennis org and region catalogs', () => {
  assertEquals(TENNIS_ORGS, [
    'kta',
    'kato',
    'kata',
    'ktfs',
    'kstf',
    'kssta',
    'kasta',
    'gj',
    'jn',
    'local',
  ]);
  assertEquals(REGION_CODES, [
    'gwangju',
    'jeonnam',
    'seoul_metro',
    'busan_ulsan_gn',
    'daegu_gb',
    'chungcheong',
    'gangwon',
    'jeju',
  ]);
});

Deno.test('shared enums expose entry fee units', () => {
  assertEquals(ENTRY_FEE_UNITS, ['per_team', 'per_person']);
});
