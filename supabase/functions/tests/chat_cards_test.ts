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
  application_deadline: '2026-06-10',
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

Deno.test('buildTournamentCards defaults regulation_fields to [] when absent', () => {
  const cards = buildTournamentCards([SAMPLE_ROW]);
  assertEquals(cards[0].regulation_fields, []);
});

Deno.test('buildTournamentCards normalizes regulation_fields jsonb', () => {
  const row: TournamentCardRow = {
    ...SAMPLE_ROW,
    regulation_fields: [
      { label: '장소', value: '진월국제테니스장' },
      { label: '시상', value: '메달' },
    ],
  };
  const cards = buildTournamentCards([row]);
  assertEquals(cards[0].regulation_fields, [
    { label: '장소', value: '진월국제테니스장' },
    { label: '시상', value: '메달' },
  ]);
});

Deno.test('buildTournamentCards caps regulation_fields at 3', () => {
  const row: TournamentCardRow = {
    ...SAMPLE_ROW,
    regulation_fields: [
      { label: '장소', value: 'A' },
      { label: '주최', value: 'B' },
      { label: '시상', value: 'C' },
      { label: '참가비', value: 'D' },
      { label: '경기방식', value: 'E' },
    ],
  };
  const cards = buildTournamentCards([row]);
  assertEquals(cards[0].regulation_fields.length, 3);
  assertEquals(cards[0].regulation_fields.map((f) => f.label), ['장소', '주최', '시상']);
});

Deno.test('buildTournamentCards drops malformed regulation_fields entries', () => {
  const row: TournamentCardRow = {
    ...SAMPLE_ROW,
    // jsonb 라 unknown — 비객체/빈값/비문자 항목은 normalizeRegulationFields 가 제거.
    regulation_fields: [
      { label: '장소', value: '코트A' },
      { label: '', value: '값없음라벨' },
      { label: '시상', value: '' },
      null,
      'garbage',
    ] as unknown,
  };
  const cards = buildTournamentCards([row]);
  assertEquals(cards[0].regulation_fields, [{ label: '장소', value: '코트A' }]);
});

Deno.test('buildTournamentCards tolerates non-array regulation_fields', () => {
  const row: TournamentCardRow = {
    ...SAMPLE_ROW,
    regulation_fields: { label: 'x', value: 'y' } as unknown,
  };
  const cards = buildTournamentCards([row]);
  assertEquals(cards[0].regulation_fields, []);
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
