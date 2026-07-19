import { assertStringIncludes } from 'std/assert/mod.ts';

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

Deno.test('cost and UGC endpoints require server-side verified age', async () => {
  for (
    const path of [
      '../chat/index.ts',
      '../clubs-create/index.ts',
      '../tournaments-submit/index.ts',
    ]
  ) {
    const endpoint = await source(path);
    assertStringIncludes(endpoint, 'requireVerifiedUser(req)');
  }
});

Deno.test('club join request checks age without blocking cancel or leave', async () => {
  const endpoint = await source('../clubs-join/index.ts');
  const requestBranch = endpoint.indexOf("if (action === 'request')");
  const cancelBranch = endpoint.indexOf("if (action === 'cancel')");
  const ageGuard = endpoint.indexOf('requireVerifiedAge(auth.supabase)', requestBranch);

  if (requestBranch < 0 || cancelBranch < 0 || ageGuard < 0) {
    throw new Error('clubs-join request age guard wiring is missing');
  }
  if (ageGuard >= cancelBranch) {
    throw new Error('age guard must stay scoped to the join request branch');
  }
});
