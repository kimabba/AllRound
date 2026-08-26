import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';

// tournaments-search 는 Deno.serve 를 top-level 에서 무조건 실행해(guard 없음) 핸들러를
// 직접 import 해서 호출할 수 없다(tournaments_search_org_test.ts 와 같은 소스 검사 방식).
// 검증 자체(활성 통과/미존재 400/DB 오류 503)는 tests/tournaments_submit_region_test.ts 의
// 공용 함수 테스트로 커버되고, 여기서는 search 가 정적 목록(REGION_CODES)이 아니라
// 그 공용 함수를 실제로 호출하는지 확인한다.
async function source(): Promise<string> {
  return await Deno.readTextFile(new URL('../tournaments-search/index.ts', import.meta.url));
}

Deno.test('search 는 지역을 정적 목록이 아니라 DB 공용 검증 함수로 확인한다', async () => {
  const endpoint = await source();
  assertStringIncludes(endpoint, "from '../_shared/regions.ts'");
  assertStringIncludes(endpoint, 'fetchActiveRegionCodes(supabase)');
  assertStringIncludes(endpoint, 'assertKnownRegions([regionCode]');
  // P7 재발 방지: isValidRegionCode 정적 검증으로 되돌아가면 안 된다(협회 JY-135/#330 과 동일 원칙).
  assertEquals(endpoint.indexOf('isValidRegionCode'), -1);
});

Deno.test('지역 검증은 rpc 호출보다 먼저 실행된다(없는 지역으로 결과 0건이 아니라 즉시 거절)', async () => {
  const endpoint = await source();
  const regionCheck = endpoint.indexOf('assertKnownRegions([regionCode]');
  const rpcCall = endpoint.indexOf("rpc('tournaments_for_user'");
  if (regionCheck < 0 || rpcCall < 0) throw new Error('region check or rpc call missing');
  if (regionCheck >= rpcCall) throw new Error('region validation must run before the rpc call');
});
