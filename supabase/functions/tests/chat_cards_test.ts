import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildTournamentCards,
  parseSelectedEntity,
  renderTournamentSearchEmptyText,
  renderTournamentSearchText,
  type TournamentCardRow,
} from '../_shared/chat_cards.ts';

const SAMPLE_ROW: TournamentCardRow = {
  id: '11111111-1111-1111-1111-111111111111',
  sport: 'tennis',
  title: '광주 생활체육 테니스 오픈',
  start_date: '2026-06-13',
  end_date: '2026-06-13',
  region: '광주',
  location: '진월국제테니스장',
  eligible_grades: ['gj_m_gold'],
  entry_fee: 30000,
  format: '복식',
};

Deno.test('buildTournamentCards maps rows to display-safe items', () => {
  const cards = buildTournamentCards([SAMPLE_ROW]);
  assertEquals(cards.length, 1);
  const c = cards[0];
  assertEquals(c.id, SAMPLE_ROW.id);
  assertEquals(c.title, '광주 생활체육 테니스 오픈');
  assertEquals(c.sport, 'tennis');
  assertEquals(c.region, '광주');
  assertEquals(c.entry_fee, 30000);
  assertEquals(c.eligible, true);
});

Deno.test('buildTournamentCards caps at 10 items', () => {
  const rows = Array.from({ length: 25 }, (_, i) => ({ ...SAMPLE_ROW, id: `id-${i}` }));
  const cards = buildTournamentCards(rows);
  assertEquals(cards.length, 10);
});

Deno.test('buildTournamentCards returns empty array for empty input', () => {
  assertEquals(buildTournamentCards([]), []);
});

Deno.test('renderTournamentSearchText summarizes results without duplicating card rows', () => {
  const text = renderTournamentSearchText([SAMPLE_ROW], {
    sport: 'tennis',
    region: '광주',
    dateRange: { from: '2026-06-15', to: '2026-06-21' },
  });

  assert(text.includes('🎾 테니스 1건'));
  assert(text.includes('아래 카드'));
  assert(!text.includes(SAMPLE_ROW.title));
});

Deno.test('renderTournamentSearchEmptyText is authoritative for precise empty filters', () => {
  const text = renderTournamentSearchEmptyText({
    sport: 'tennis',
    region: null,
    dateRange: { from: '2026-06-15', to: '2026-06-21' },
  });

  assert(text.includes('조건에 맞는 테니스 대회가 없습니다'));
  assert(text.includes('2026-06-15 ~ 2026-06-21'));
  assert(!text.includes('현재 매치업 DB에 해당 정보가 등록되어 있지 않습니다'));
});

Deno.test('parseSelectedEntity accepts a valid tournament entity', () => {
  const result = parseSelectedEntity({
    type: 'tournament',
    id: '11111111-1111-1111-1111-111111111111',
  });
  assert(result.ok);
  if (result.ok) {
    assertEquals(result.value.type, 'tournament');
    assertEquals(result.value.id, '11111111-1111-1111-1111-111111111111');
  }
});

Deno.test('parseSelectedEntity accepts a valid club entity', () => {
  const result = parseSelectedEntity({ type: 'club', id: '22222222-2222-2222-2222-222222222222' });
  assert(result.ok);
  if (result.ok) assertEquals(result.value.type, 'club');
});

Deno.test('parseSelectedEntity rejects invalid entity type', () => {
  const result = parseSelectedEntity({ type: 'user', id: '11111111-1111-1111-1111-111111111111' });
  assert(!result.ok);
});

Deno.test('parseSelectedEntity rejects malformed id', () => {
  const result = parseSelectedEntity({ type: 'tournament', id: 'not-a-uuid' });
  assert(!result.ok);
});

Deno.test('parseSelectedEntity returns ok=false for null/undefined', () => {
  assert(!parseSelectedEntity(undefined).ok);
  assert(!parseSelectedEntity(null).ok);
});
