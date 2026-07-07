import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildClubCards,
  buildTournamentCards,
  type ClubCardRow,
  type ClubDetailRow,
  parseSelectedEntity,
  renderClubDetailText,
  renderClubSearchEmptyText,
  renderClubSearchText,
  renderTournamentDetailIntroText,
  renderTournamentDetailText,
  renderTournamentSearchEmptyText,
  renderTournamentSearchText,
  type TournamentCardRow,
  type TournamentDetailRow,
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

Deno.test('renderTournamentSearchEmptyText surfaces the my-grade filter so users can retry', () => {
  const text = renderTournamentSearchEmptyText({
    sport: 'tennis',
    region: null,
    dateRange: { from: '2026-07-06', to: '2026-07-12' },
    onlyMyGrade: true,
  });

  assert(text.includes('내 등급 기준'));
  assert(text.includes('내 등급에 참가 가능한 대회만'));

  // onlyMyGrade가 없으면 등급 문구도 노출하지 않는다.
  const without = renderTournamentSearchEmptyText({
    sport: 'tennis',
    region: null,
    dateRange: { from: '2026-07-06', to: '2026-07-12' },
  });
  assert(!without.includes('내 등급'));
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

// ==========================================================================
// Tournament detail
// ==========================================================================

const SAMPLE_DETAIL_ROW: TournamentDetailRow = {
  ...SAMPLE_ROW,
  organizer: '광주테니스협회',
  prize: '우승 트로피',
  regulation_fields: [{ label: '접수처', value: '협회 사무국' }],
  regulation_body: '참가 자격은 동호인 등록 선수에 한한다.',
  regulation_notes: ['참가비로 스포츠공제보험 가입'],
  source_url: 'https://example.com/notice/1',
};

Deno.test('renderTournamentDetailText renders full markdown detail', () => {
  const text = renderTournamentDetailText(SAMPLE_DETAIL_ROW);
  assert(text.includes('## 광주 생활체육 테니스 오픈'));
  assert(text.includes('- 일정: 2026-06-13'));
  assert(text.includes('- 장소: 광주 진월국제테니스장'));
  assert(text.includes('- 접수 마감: 2026-06-10'));
  assert(text.includes('- 참가비: 30,000원'));
  assert(text.includes('- 주최: 광주테니스협회'));
  assert(text.includes('### 요강'));
  assert(text.includes('접수처: 협회 사무국'));
  assert(text.includes('참가 자격은 동호인 등록 선수에 한한다.'));
  assert(text.includes('※ 참가비로 스포츠공제보험 가입'));
  assert(text.includes('[공식 페이지에서 보기](https://example.com/notice/1)'));
});

Deno.test('renderTournamentDetailText omits missing optional sections', () => {
  const text = renderTournamentDetailText({
    ...SAMPLE_DETAIL_ROW,
    application_deadline: null,
    entry_fee: null,
    organizer: null,
    prize: null,
    regulation_fields: undefined,
    regulation_body: null,
    regulation_notes: null,
    source_url: null,
  });
  assert(text.includes('## 광주 생활체육 테니스 오픈'));
  assert(!text.includes('접수 마감'));
  assert(!text.includes('참가비'));
  assert(!text.includes('### 요강'));
  assert(!text.includes('※'));
  assert(!text.includes('공식 페이지'));
});

Deno.test('renderTournamentDetailText drops non-http source_url (no unsafe link)', () => {
  const text = renderTournamentDetailText({
    ...SAMPLE_DETAIL_ROW,
    source_url: 'javascript:alert(1)',
  });
  assert(!text.includes('공식 페이지'));
  assert(!text.includes('javascript'));
});

Deno.test('renderTournamentDetailIntroText points users to cards for application info', () => {
  const text = renderTournamentDetailIntroText([SAMPLE_ROW], {
    sport: 'tennis',
    region: '광주',
  });
  assert(text.includes('🎾 테니스 1건'));
  assert(text.includes('아래 카드'));
  assert(text.includes("'상세 보기'"));
  assert(!text.includes(SAMPLE_ROW.title));
});

// ==========================================================================
// Club cards
// ==========================================================================

const SAMPLE_CLUB_ROW: ClubCardRow = {
  id: '22222222-2222-2222-2222-222222222222',
  sport: 'tennis',
  name: '광주 아침테니스',
  region: '광주',
  description: '평일 아침에 함께 치는 클럽입니다.',
  member_count: 24,
  monthly_fee: 20000,
  meeting_days: ['화', '목'],
  gender_preference: 'mixed',
};

Deno.test('buildClubCards maps rows to the fixed card contract', () => {
  const cards = buildClubCards([SAMPLE_CLUB_ROW]);
  assertEquals(cards.length, 1);
  assertEquals(cards[0], {
    id: SAMPLE_CLUB_ROW.id,
    name: '광주 아침테니스',
    sport: 'tennis',
    region: '광주',
    description: '평일 아침에 함께 치는 클럽입니다.',
    member_count: 24,
    monthly_fee: 20000,
    meeting_days: ['화', '목'],
    gender_preference: 'mixed',
  });
});

Deno.test('buildClubCards caps at 10 items and tolerates empty input', () => {
  const rows = Array.from({ length: 25 }, (_, i) => ({ ...SAMPLE_CLUB_ROW, id: `id-${i}` }));
  assertEquals(buildClubCards(rows).length, 10);
  assertEquals(buildClubCards([]), []);
});

Deno.test('renderClubSearchText summarizes results without duplicating card rows', () => {
  const text = renderClubSearchText([SAMPLE_CLUB_ROW], { sport: 'tennis', region: '광주' });
  assert(text.includes('🎾 테니스 클럽 1건'));
  assert(text.includes('(광주)'));
  assert(text.includes('아래 카드'));
  assert(!text.includes(SAMPLE_CLUB_ROW.name));
});

Deno.test('renderClubSearchEmptyText names the filters and suggests retry', () => {
  const text = renderClubSearchEmptyText({ sport: 'futsal', region: '광주' });
  assert(text.includes('조건에 맞는 풋살 클럽이 없습니다'));
  assert(text.includes('(광주)'));
  assert(text.includes('클럽 탭'));

  const noFilter = renderClubSearchEmptyText({ region: null });
  assert(noFilter.includes('조건에 맞는 클럽이 없습니다.'));
});

Deno.test('renderClubDetailText renders full markdown detail', () => {
  const club: ClubDetailRow = {
    ...SAMPLE_CLUB_ROW,
    address: '광주 남구 진월동 123',
    contact: '오픈채팅 https://open.kakao.com/abc',
  };
  const text = renderClubDetailText(club);
  assert(text.includes('## 광주 아침테니스'));
  assert(text.includes('- 종목: 테니스'));
  assert(text.includes('- 지역: 광주'));
  assert(text.includes('- 주소: 광주 남구 진월동 123'));
  assert(text.includes('- 정기 모임: 화, 목'));
  assert(text.includes('- 월 회비: 20,000원'));
  assert(text.includes('- 멤버: 24명'));
  assert(text.includes('- 성별: 혼성'));
  assert(text.includes('- 연락처: 오픈채팅 https://open.kakao.com/abc'));
  assert(text.includes('평일 아침에 함께 치는 클럽입니다.'));
});

Deno.test('renderClubDetailText omits missing optional fields', () => {
  const club: ClubDetailRow = {
    ...SAMPLE_CLUB_ROW,
    region: null,
    description: null,
    monthly_fee: null,
    meeting_days: [],
    gender_preference: null,
    address: null,
    contact: null,
  };
  const text = renderClubDetailText(club);
  assert(text.includes('## 광주 아침테니스'));
  assert(text.includes('- 멤버: 24명'));
  assert(!text.includes('지역'));
  assert(!text.includes('주소'));
  assert(!text.includes('정기 모임'));
  assert(!text.includes('월 회비'));
  assert(!text.includes('성별'));
  assert(!text.includes('연락처'));
});
