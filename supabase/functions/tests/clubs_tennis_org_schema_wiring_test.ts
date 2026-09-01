import { assert, assertStringIncludes } from 'std/assert/mod.ts';

async function source(relativePath: string): Promise<string> {
  return await Deno.readTextFile(new URL(relativePath, import.meta.url));
}

Deno.test('club profile endpoints use the current user_tennis_orgs division column', async () => {
  for (
    const path of [
      '../clubs-join/index.ts',
      '../clubs-inquiries/index.ts',
    ]
  ) {
    const endpoint = await source(path);

    assertStringIncludes(
      endpoint,
      ".from('user_tennis_orgs').select('user_id, org, division, score')",
    );
    assertStringIncludes(endpoint, 'division: row.division');
    assert(
      !endpoint.includes('division_local'),
      `${path} must not query the removed user_tennis_orgs.division_local column`,
    );
  }
});
