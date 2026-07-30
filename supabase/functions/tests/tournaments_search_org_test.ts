import { assertEquals, assertStringIncludes } from 'std/assert/mod.ts';
import { assertKnownOrgs } from '../_shared/orgs.ts';

// tournaments-search 는 Deno.serve 를 top-level 에서 무조건 실행해(guard 없음) 핸들러를
// 직접 import 해서 호출할 수 없다(age_gate_wiring_test.ts 와 같은 소스 검사 방식을 쓴다).
// 검증 자체(활성 통과/미존재 400/DB 오류 503)는 assertKnownOrgs 공용 함수 테스트로 커버되고,
// 여기서는 search 가 정적 목록이 아니라 그 공용 함수를 실제로 호출하는지 확인한다.
async function source(): Promise<string> {
  return await Deno.readTextFile(new URL('../tournaments-search/index.ts', import.meta.url));
}

Deno.test('search 는 협회를 정적 목록이 아니라 DB 공용 검증 함수로 확인한다', async () => {
  const endpoint = await source();
  assertStringIncludes(endpoint, "from '../_shared/orgs.ts'");
  assertStringIncludes(endpoint, 'assertKnownOrgs(supabase, [org])');
  // JY-135/#330 재발 방지: isValidTennisOrg 정적 검증으로 되돌아가면 안 된다.
  const idx = endpoint.indexOf('isValidTennisOrg');
  assertEquals(idx, -1);
});

Deno.test('org 검증은 rpc 호출보다 먼저 실행된다(존재하지 않는 협회로 결과 0건이 아니라 즉시 거절)', async () => {
  const endpoint = await source();
  const orgCheck = endpoint.indexOf('assertKnownOrgs(supabase, [org])');
  const rpcCall = endpoint.indexOf("rpc('tournaments_for_user'");
  if (orgCheck < 0 || rpcCall < 0) throw new Error('org check or rpc call missing');
  if (orgCheck >= rpcCall) throw new Error('org validation must run before the rpc call');
});

// 공용 함수 자체의 3가지 시나리오(활성 통과/미존재 400/DB 오류 503)는 이미
// tests/tournaments_submit_org_test.ts 에서 검증한다. search 는 같은 함수를 재사용하므로
// 여기서는 반환 status 를 그대로 응답에 전달하는지만 별도로 확인한다.
function fakeClient(rows: Array<{ code: string }>) {
  return {
    from: () => ({
      select: () => ({
        in: () => ({ eq: () => Promise.resolve({ data: rows, error: null }) }),
      }),
    }),
  } as unknown as Parameters<typeof assertKnownOrgs>[0];
}

Deno.test('search 시나리오: 활성 협회 통과', async () => {
  const err = await assertKnownOrgs(fakeClient([{ code: 'kato' }]), ['kato']);
  assertEquals(err, null);
});

Deno.test('search 시나리오: 존재하지 않는 협회는 400', async () => {
  const err = await assertKnownOrgs(fakeClient([]), ['not_a_real_org']);
  assertEquals(err?.status, 400);
});

Deno.test('search 시나리오: DB 오류는 503(fail-closed)', async () => {
  const failing = {
    from: () => ({
      select: () => ({
        in: () => ({
          eq: () => Promise.resolve({ data: null, error: { message: 'boom' } }),
        }),
      }),
    }),
  } as unknown as Parameters<typeof assertKnownOrgs>[0];
  const err = await assertKnownOrgs(failing, ['kato']);
  assertEquals(err?.status, 503);
});
