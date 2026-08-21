import { assert, assertEquals, assertStringIncludes } from 'std/assert/mod.ts';

const migrationUrl = new URL(
  '../../migrations/20260809124140_seed_tennis_match_rules.sql',
  import.meta.url,
);

const expectedTitles = [
  '테니스 게임 스코어와 듀스는 어떻게 계산하나요?',
  '세트와 매치는 몇 게임, 몇 세트를 이겨야 하나요?',
  '7포인트 타이브레이크의 점수와 서브 순서는 어떻게 되나요?',
  '서브 차례와 서브 위치의 기본 규칙은 무엇인가요?',
  '서브 렛과 일반 렛은 언제 다시 하나요?',
  '코트는 언제 바꾸나요?',
  '라인에 닿으면 인인가요? 인·아웃은 어떻게 판단하나요?',
  '복식의 서브와 리시브 순서는 어떻게 정하나요?',
] as const;

const officialSource =
  'World Tennis(구 International Tennis Federation, ITF), 2026 Rules of Tennis (English)';
const officialUrl = 'https://www.itftennis.com/media/7221/2026-rules-of-tennis-english.pdf';

async function readMigration(): Promise<string> {
  return await Deno.readTextFile(migrationUrl);
}

Deno.test('tennis rule seed covers every requested core match rule', async () => {
  const sql = await readMigration();

  for (const title of expectedTitles) {
    assertStringIncludes(sql, title);
    assertEquals(
      sql.split(title).length - 1,
      1,
      `seed title must occur exactly once: ${title}`,
    );
  }

  for (
    const keyword of ['듀스', '타이브레이크', '서브 위치', '렛', '코트 교대', '인·아웃', '복식']
  ) {
    assertStringIncludes(sql, keyword);
  }
});

Deno.test('each tennis rule summary carries the official 2026 primary source', async () => {
  const sql = await readMigration();
  const bodies = [...sql.matchAll(/\$body\$([\s\S]*?)\$body\$/g)].map((match) => match[1]);

  assertEquals(bodies.length, expectedTitles.length);
  for (const body of bodies) {
    assertStringIncludes(body, officialSource);
    assertStringIncludes(body, officialUrl);
  }
});

Deno.test('tennis rule seed is title-idempotent and leaves embeddings pending', async () => {
  const sql = await readMigration();

  assertStringIncludes(sql, 'update public.rule_articles as r');
  assertStringIncludes(sql, 'where r.sport = s.sport\n    and r.title = s.title');
  assertStringIncludes(sql, 'where not exists (');
  assertStringIncludes(sql, 'from updated as u');
  assertStringIncludes(sql, 'embedding = null');
  assertStringIncludes(sql, 'embedding_updated_at = null');
  assertStringIncludes(sql, 'null::vector(768)');
  assertStringIncludes(sql, 'null::timestamptz');

  const updateBlock = sql.slice(
    sql.indexOf('update public.rule_articles as r'),
    sql.indexOf('returning r.sport, r.title'),
  );
  assert(
    !updateBlock.includes('published ='),
    're-running the seed must preserve an operator-unpublished article',
  );

  assert(
    !sql.toLowerCase().includes('delete from public.rule_articles'),
    'idempotency must not delete existing user data',
  );
});
