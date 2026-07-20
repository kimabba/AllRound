import { assertEquals } from 'std/assert/mod.ts';

import { buildDbCitations, buildTournamentCardBlocks } from '../chat/stream.ts';
import type { SemanticRule, SemanticTournament, VenueRow } from '../chat/types.ts';

function tourn(id: string, over: Partial<SemanticTournament> = {}): SemanticTournament {
  return {
    id,
    sport: 'tennis',
    title: `T-${id}`,
    start_date: '2026-08-01',
    region: null,
    eligible_grades: [],
    regulation_fields: [],
    regulation_body: null,
    similarity: 0.9,
    ...over,
  };
}

function rule(id: string): SemanticRule {
  return { id, sport: 'tennis', category: 'c', title: `R-${id}`, body: 'b', similarity: 0.8 };
}

function venue(id: string): VenueRow {
  return {
    id,
    sport: 'tennis',
    name: `V-${id}`,
    region: '서울',
    address: null,
    venue_type: 'court',
    court_count: null,
    phone: null,
    website: null,
  };
}

type CardBlocks = { blocks: Array<{ type: string; entity: string; items: Array<{ location: string | null }> }> };

Deno.test('buildDbCitations: 소스별 매핑 + 순서(tournaments→rules→venues)', () => {
  const cites = buildDbCitations([tourn('t1')], [rule('r1')], [venue('v1')]);
  assertEquals(cites, [
    { type: 'db', source: 'tournaments', id: 't1', title: 'T-t1' },
    { type: 'db', source: 'rules', id: 'r1', title: 'R-r1' },
    { type: 'db', source: 'venues', id: 'v1', title: 'V-v1' },
  ]);
});

Deno.test('buildDbCitations: 소스별 개수 상한 (t 5 / r 3 / v 15)', () => {
  const ts = Array.from({ length: 7 }, (_, i) => tourn(`t${i}`));
  const rs = Array.from({ length: 4 }, (_, i) => rule(`r${i}`));
  const vs = Array.from({ length: 16 }, (_, i) => venue(`v${i}`));
  const cites = buildDbCitations(ts, rs, vs);
  assertEquals(cites.filter((c) => c.source === 'tournaments').length, 5);
  assertEquals(cites.filter((c) => c.source === 'rules').length, 3);
  assertEquals(cites.filter((c) => c.source === 'venues').length, 15);
});

Deno.test('buildTournamentCardBlocks: 빈 입력은 null', () => {
  assertEquals(buildTournamentCardBlocks([]), null);
});

Deno.test('buildTournamentCardBlocks: cards 블록 구조 + 최대 10개', () => {
  const ts = Array.from({ length: 12 }, (_, i) => tourn(`t${i}`));
  const out = buildTournamentCardBlocks(ts) as CardBlocks;
  assertEquals(out.blocks.length, 1);
  assertEquals(out.blocks[0].type, 'cards');
  assertEquals(out.blocks[0].entity, 'tournament');
  assertEquals(out.blocks[0].items.length, 10);
});

Deno.test('buildTournamentCardBlocks: 요강 장소 라벨을 location으로 추출', () => {
  const t = tourn('t1', { regulation_fields: [{ label: '경기장', value: '올림픽테니스장' }] });
  const out = buildTournamentCardBlocks([t]) as CardBlocks;
  assertEquals(out.blocks[0].items[0].location, '올림픽테니스장');
});

Deno.test('buildTournamentCardBlocks: 장소 라벨 없으면 location null', () => {
  const t = tourn('t1', { regulation_fields: [{ label: '참가비', value: '1만원' }] });
  const out = buildTournamentCardBlocks([t]) as CardBlocks;
  assertEquals(out.blocks[0].items[0].location, null);
});
