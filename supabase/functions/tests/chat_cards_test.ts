import { assert, assertEquals } from 'std/assert/mod.ts';
import {
  buildClubCards,
  buildRefineChip,
  buildTournamentCards,
  type ClubCardRow,
  type ClubDetailRow,
  isGradeRegisteredForSport,
  isTournamentCardRow,
  parseSelectedEntity,
  parseTournamentRefine,
  renderClubDetailText,
  renderClubSearchEmptyText,
  renderClubSearchText,
  renderTournamentApplicationGuideText,
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

Deno.test('renderTournamentApplicationGuideText points users to cards without fake list rows', () => {
  const text = renderTournamentApplicationGuideText([SAMPLE_ROW], {
    sport: 'futsal',
    region: null,
  });

  assert(text.includes('현재 신청 가능한 풋살 대회 1건'));
  assert(text.includes('아래 카드'));
  assert(text.includes('원본 링크'));
  assert(!text.includes('추천 대회 목록'));
  assert(!text.includes(SAMPLE_ROW.title));
});

Deno.test('renderTournamentApplicationGuideText gives an empty-state application guide', () => {
  const text = renderTournamentApplicationGuideText([], {
    sport: 'futsal',
    region: '광주',
  });

  assert(text.includes('현재 신청 가능한 풋살 대회가 없습니다'));
  assert(text.includes('광주'));
  assert(text.includes('협회 공식 홈페이지'));
});

Deno.test('isTournamentCardRow validates RPC card rows before rendering cards', () => {
  assert(isTournamentCardRow(SAMPLE_ROW));
  assert(!isTournamentCardRow({ ...SAMPLE_ROW, sport: 'basketball' }));
  assert(!isTournamentCardRow({ ...SAMPLE_ROW, eligible_grades: [1, 2, 3] }));
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

// ── 정제 칩 (JY-101) ──────────────────────────────────────────────

Deno.test('parseTournamentRefine: 유효 페이로드 파싱', () => {
  const r = parseTournamentRefine({
    sport: 'tennis',
    region_code: 'gwangju',
    date_from: '2026-07-01',
    date_to: '2026-07-31',
    only_my_grade: true,
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.sport, 'tennis');
    assertEquals(r.value.region_code, 'gwangju');
    assertEquals(r.value.only_my_grade, true);
  }
});

Deno.test('parseTournamentRefine: only_my_grade 없으면 거부', () => {
  assertEquals(parseTournamentRefine({ sport: 'tennis' }).ok, false);
});

Deno.test('parseTournamentRefine: 잘못된 sport 거부', () => {
  assertEquals(
    parseTournamentRefine({ sport: 'golf', only_my_grade: false }).ok,
    false,
  );
});

Deno.test('parseTournamentRefine: null/비객체 거부', () => {
  assertEquals(parseTournamentRefine(null).ok, false);
  assertEquals(parseTournamentRefine('x').ok, false);
});

Deno.test('buildRefineChip: 전체(false) → 내 등급만 칩', () => {
  const chip = buildRefineChip(false, {
    sport: 'tennis',
    region_code: 'gwangju',
    date_from: null,
    date_to: null,
  });
  assertEquals(chip.label, '내 등급만 보기');
  assertEquals(chip.refine.only_my_grade, true);
  assertEquals(chip.refine.region_code, 'gwangju');
});

Deno.test('buildRefineChip: 내 등급(true) → 전체 보기 칩', () => {
  const chip = buildRefineChip(true, {
    sport: 'tennis',
    region_code: null,
    date_from: null,
    date_to: null,
  });
  assertEquals(chip.label, '전체 대회 보기');
  assertEquals(chip.refine.only_my_grade, false);
});

Deno.test('isGradeRegisteredForSport: 테니스는 division_codes 채워짐이 조건', () => {
  assert(isGradeRegisteredForSport('tennis', [{ division_codes: ['gj_m_open'] }], []));
  assert(!isGradeRegisteredForSport('tennis', [{ division_codes: [] }], []));
});

Deno.test('isGradeRegisteredForSport: 풋살은 grade 존재가 조건', () => {
  assert(isGradeRegisteredForSport('futsal', [], ['y1to3']));
  assert(!isGradeRegisteredForSport('futsal', [], [null, undefined]));
});

Deno.test('isGradeRegisteredForSport: sport null 이면 false', () => {
  assertEquals(isGradeRegisteredForSport(null, [{ division_codes: ['x'] }], ['y']), false);
});

// ── codex 리뷰 후속 (JY-101) ──────────────────────────────────────

Deno.test('buildTournamentCards: eligible=false 면 배지 숨김', () => {
  const cards = buildTournamentCards([SAMPLE_ROW], false);
  assertEquals(cards[0].eligible, false);
});

Deno.test('buildTournamentCards: eligible 기본값은 true(자격자 검색)', () => {
  assertEquals(buildTournamentCards([SAMPLE_ROW])[0].eligible, true);
});

Deno.test('parseTournamentRefine: 잘못된 date 형식은 null 로 떨군다', () => {
  const r = parseTournamentRefine({
    only_my_grade: true,
    date_from: 'garbage',
    date_to: '2026-07-31',
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.date_from, null);
    assertEquals(r.value.date_to, '2026-07-31');
  }
});

Deno.test('parseTournamentRefine: from>to 뒤집힘은 둘 다 떨군다', () => {
  const r = parseTournamentRefine({
    only_my_grade: false,
    date_from: '2026-08-01',
    date_to: '2026-07-01',
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.date_from, null);
    assertEquals(r.value.date_to, null);
  }
});

Deno.test('parseTournamentRefine: 정상 ISO 날짜 범위는 유지', () => {
  const r = parseTournamentRefine({
    only_my_grade: true,
    date_from: '2026-07-01',
    date_to: '2026-07-31',
  });
  assert(r.ok);
  if (r.ok) {
    assertEquals(r.value.date_from, '2026-07-01');
    assertEquals(r.value.date_to, '2026-07-31');
  }
});
