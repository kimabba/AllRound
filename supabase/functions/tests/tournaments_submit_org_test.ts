import { assertEquals } from 'std/assert/mod.ts';
import { assertKnownOrgs } from '../_shared/orgs.ts';

// 협회 정본은 DB tennis_orgs 다(JY-135). 정적 목록으로 검증하면 DB 에 협회를
// 추가해도 제보가 거절된다 — "행 INSERT 하나로 반영" 이 깨진다.
function fakeClient(rows: Array<{ code: string }>) {
  return {
    from: () => ({
      select: () => ({
        in: () => ({ eq: () => Promise.resolve({ data: rows, error: null }) }),
      }),
    }),
  } as unknown as Parameters<typeof assertKnownOrgs>[0];
}

Deno.test('DB 에 있는 활성 협회는 통과한다', async () => {
  const err = await assertKnownOrgs(fakeClient([{ code: 'seoul' }]), ['seoul']);
  assertEquals(err, null);
});

Deno.test('DB 에 없는 협회는 거절한다(400)', async () => {
  const err = await assertKnownOrgs(fakeClient([]), ['nope']);
  assertEquals(err?.message, 'invalid org: nope');
  assertEquals(err?.status, 400);
});

Deno.test('DB 조회 실패 시 거절한다(fail-closed, 503)', async () => {
  const failing = {
    from: () => ({
      select: () => ({
        in: () => ({
          eq: () => Promise.resolve({ data: null, error: { message: 'boom' } }),
        }),
      }),
    }),
  } as unknown as Parameters<typeof assertKnownOrgs>[0];
  const err = await assertKnownOrgs(failing, ['gj']);
  assertEquals(err?.message, 'org 검증에 실패했습니다');
  assertEquals(err?.status, 503);
});
