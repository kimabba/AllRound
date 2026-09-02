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
      '../semantic-search/index.ts', // Gemini 비용 발생 → 자격 필요
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

// clubs-join 은 serviceClient 로 쓰므로 RLS 가 우회된다 → Edge 가 경계다.
// 게이트는 fail-closed(예외 목록 외 전부 차단)여야 새 action 이 자동 보호된다.
Deno.test('club join gates every action except reads and self-exit', async () => {
  const endpoint = await source('../clubs-join/index.ts');

  assertStringIncludes(endpoint, "new Set(['list_members', 'cancel', 'leave'])");
  assertStringIncludes(endpoint, 'if (!ungatedActions.has(action))');
  assertStringIncludes(endpoint, 'requireEligibility(auth.supabase)');

  // 가드가 개별 분기보다 앞서야 이후 추가되는 action 이 기본 차단된다.
  const guard = endpoint.indexOf('ungatedActions.has(action)');
  const firstBranch = endpoint.indexOf("if (action === '");
  assert(
    guard >= 0 && firstBranch >= 0 && guard < firstBranch,
    'eligibility gate must run before the action branches (fail-closed)',
  );
});

// serviceClient 로 쓰는 나머지 클럽 endpoint 도 쓰기 경로에 자격 게이트가 있어야 한다.
Deno.test('service-role club endpoints gate writes but keep reads open', async () => {
  for (
    const path of ['../clubs-inquiries/index.ts', '../clubs-review-join/index.ts']
  ) {
    const endpoint = await source(path);
    assertStringIncludes(endpoint, "req.method !== 'GET'");
    assertStringIncludes(endpoint, 'requireEligibility(auth.supabase)');
  }
});

// 동의 게이트는 화면이 아니라 서버에 있어야 한다. 체크박스만으로는 JWT 로
// 엔드포인트를 직접 호출하는 경로를 못 막고, 동의를 받았다는 흔적도 남지 않는다.
Deno.test('send-otp requires consent before it touches the phone number', async () => {
  const endpoint = await source('../send-otp/index.ts');

  assertStringIncludes(endpoint, '?.consent === true');
  assertStringIncludes(endpoint, 'phone_consent_at');

  // 동의 검사가 번호 해싱·발송보다 앞서야 fail-closed 다.
  const consentGuard = endpoint.indexOf('if (!consent)');
  const hashing = endpoint.indexOf('hashPhone(');
  const sending = endpoint.indexOf('sendSms(');
  assert(consentGuard >= 0, 'send-otp must reject requests without consent');
  assert(
    consentGuard < hashing && consentGuard < sending,
    'consent guard must run before the number is hashed or sent (fail-closed)',
  );

  // 동의 기록 실패를 삼키면 근거 없이 번호가 수탁자로 나간다.
  const record = endpoint.indexOf('consentError');
  assert(record >= 0 && record < sending, 'consent must be recorded before sending');
});
