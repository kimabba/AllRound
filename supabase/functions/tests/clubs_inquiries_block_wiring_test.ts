import { assert, assertStringIncludes } from 'std/assert/mod.ts';

// clubs-inquiries 는 Deno.serve 를 top-level 에서 무조건 실행해(guard 없음) 핸들러를
// 직접 import 해서 호출할 수 없다 — age_gate_wiring_test.ts 와 같은 소스 검사 방식을 쓴다.
//
// 회귀 대상: isBlockedPair 가 존재하지 않는 컬럼(blocked_user_id)을 조회해 매 호출이
// 에러였고, 그 에러를 삼켜 "차단 아님"으로 fail-open 됐던 버그. user_blocks 의 실제
// 컬럼은 blocker_id/blocked_id 뿐이다(id 컬럼 없음).
async function source(): Promise<string> {
  return await Deno.readTextFile(new URL('../clubs-inquiries/index.ts', import.meta.url));
}

Deno.test('isBlockedPair queries the real user_blocks columns, not the nonexistent blocked_user_id/id', async () => {
  const endpoint = await source();
  const start = endpoint.indexOf('async function isBlockedPair');
  const end = endpoint.indexOf('\n}', start);
  if (start < 0 || end < 0) throw new Error('isBlockedPair not found');
  const fn = endpoint.slice(start, end);

  assertStringIncludes(fn, "'user_blocks'");
  assertStringIncludes(fn, "'blocked_id'");
  assert(
    !fn.includes('blocked_user_id'),
    'isBlockedPair must not query the nonexistent blocked_user_id column',
  );
  assert(
    !fn.includes(".select('id')"),
    'isBlockedPair must not select the nonexistent id column on user_blocks',
  );
});

Deno.test('isBlockedPair fails closed (throws) on a query error instead of swallowing it', async () => {
  const endpoint = await source();
  const start = endpoint.indexOf('async function isBlockedPair');
  const end = endpoint.indexOf('\n}', start);
  if (start < 0 || end < 0) throw new Error('isBlockedPair not found');
  const fn = endpoint.slice(start, end);

  assertStringIncludes(fn, 'const { data, error }');
  assertStringIncludes(fn, 'if (error) throw');
});
