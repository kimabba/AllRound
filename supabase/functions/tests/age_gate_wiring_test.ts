import { assert, assertStringIncludes } from 'std/assert/mod.ts';

async function source(relativePath: string): Promise<string> {
  return await Deno.readTextFile(
    new URL(relativePath, import.meta.url),
  );
}

Deno.test('shared age guard uses the database age source of truth', async () => {
  const auth = await source('../_shared/auth.ts');
  assertStringIncludes(auth, "rpc('has_verified_signup_age')");
  assertStringIncludes(auth, 'verified !== true');
});

Deno.test('eligibility guard uses the database standing predicate', async () => {
  const auth = await source('../_shared/auth.ts');
  assertStringIncludes(auth, "rpc('is_eligible_member')");
});

Deno.test('participation and cost endpoints require server-side eligibility', async () => {
  for (
    const path of [
      '../chat/index.ts',
      '../clubs-create/index.ts',
      '../tournaments-submit/index.ts',
    ]
  ) {
    const endpoint = await source(path);
    assertStringIncludes(endpoint, 'requireEligibleMember(req)');
  }
});

// 순환 의존 회귀 가드: 전화번호 인증을 "얻는" 경로가 자격을 요구하면
// 아무도 인증을 시작할 수 없게 된다. OTP endpoint 는 연령 게이트까지만 쓴다.
Deno.test('otp endpoints must not require eligibility (would be circular)', async () => {
  const sendOtp = await source('../send-otp/index.ts');
  assertStringIncludes(sendOtp, 'requireVerifiedUser(req)');
  assert(
    !sendOtp.includes('requireEligibleMember'),
    'send-otp must not require eligibility: verifying a phone would require an already verified phone',
  );

  const verifyOtp = await source('../verify-otp/index.ts');
  assert(
    !verifyOtp.includes('requireEligibleMember'),
    'verify-otp must not require eligibility: it is the path that grants eligibility',
  );
});

Deno.test('club join request checks eligibility without blocking cancel or leave', async () => {
  const endpoint = await source('../clubs-join/index.ts');
  const requestBranch = endpoint.indexOf("if (action === 'request')");
  const cancelBranch = endpoint.indexOf("if (action === 'cancel')");
  const guard = endpoint.indexOf('requireEligibility(auth.supabase)', requestBranch);

  if (requestBranch < 0 || cancelBranch < 0 || guard < 0) {
    throw new Error('clubs-join request eligibility guard wiring is missing');
  }
  if (guard >= cancelBranch) {
    throw new Error('eligibility guard must stay scoped to the join request branch');
  }
});
