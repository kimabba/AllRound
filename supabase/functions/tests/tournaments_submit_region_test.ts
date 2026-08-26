import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';
import { assertKnownRegions, fetchActiveRegionCodes } from '../_shared/regions.ts';

// 지역 정본은 DB regions 다(P7). 정적 목록(REGION_CODES)으로 검증하면 지역을 DB 에
// 추가해도 제보가 거절된다 — 협회(JY-135, #330)와 같은 원칙.
function fakeClient(rows: Array<{ code: string }>) {
  return {
    from: () => ({
      select: () => ({ eq: () => Promise.resolve({ data: rows, error: null }) }),
    }),
  } as unknown as Parameters<typeof fetchActiveRegionCodes>[0];
}

Deno.test('활성 지역 코드를 DB 에서 집합으로 읽는다', async () => {
  const result = await fetchActiveRegionCodes(fakeClient([{ code: 'gwangju' }, { code: 'seoul' }]));
  if ('status' in result) throw new Error('카탈로그 조회가 실패로 처리됐다');
  assertEquals(result.codes, new Set(['gwangju', 'seoul']));
});

Deno.test('DB 조회 실패 시 거절한다(fail-closed, 503)', async () => {
  const failing = {
    from: () => ({
      select: () => ({
        eq: () => Promise.resolve({ data: null, error: { message: 'boom' } }),
      }),
    }),
  } as unknown as Parameters<typeof fetchActiveRegionCodes>[0];
  const result = await fetchActiveRegionCodes(failing);
  if (!('status' in result)) throw new Error('DB 오류인데 통과됐다');
  assertEquals(result.message, 'region 카탈로그 조회에 실패했습니다');
  assertEquals(result.status, 503);
});

Deno.test('DB 에 있는 활성 지역은 통과한다', () => {
  const err = assertKnownRegions(['gwangju'], new Set(['gwangju', 'seoul']));
  assertEquals(err, null);
});

Deno.test('DB 에 없는 지역은 거절한다(400)', () => {
  const err = assertKnownRegions(['nope'], new Set(['gwangju']));
  assertEquals(err?.message, 'invalid region_code: nope');
  assertEquals(err?.status, 400);
});

Deno.test('deprecated 묶음 코드(seoul_metro)는 활성 집합에 없어 거절된다 — 정적 검증 때와 같은 동작', () => {
  // regions 테이블에서 seoul_metro 등 다중시도 권역은 is_active=false 다
  // (20260710030000). 정적 REGION_CODES 도 이미 제외하고 있었으므로 회귀가 아니다.
  const err = assertKnownRegions(['seoul_metro'], new Set(['seoul', 'gyeonggi', 'incheon']));
  assertEquals(err?.status, 400);
});

// submit 이 정적 목록이 아니라 DB 공용 검증 함수를 실제로 호출하는지 소스로 확인한다
// (tournaments_search_org_test.ts 와 같은 방식).
Deno.test('submit 은 지역을 정적 목록이 아니라 DB 공용 검증 함수로 확인한다', async () => {
  const endpoint = await Deno.readTextFile(
    new URL('../tournaments-submit/index.ts', import.meta.url),
  );
  assertStringIncludes(endpoint, "from '../_shared/regions.ts'");
  assertStringIncludes(endpoint, 'assertKnownRegions([body.region_code]');
  // P7 재발 방지: isValidRegionCode 정적 검증으로 되돌아가면 안 된다.
  assertEquals(endpoint.indexOf('isValidRegionCode'), -1);
});
