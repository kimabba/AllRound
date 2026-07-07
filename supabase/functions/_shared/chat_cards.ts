// Chat a2ui 카드 빌더 + selected_entity 검증 (순수 함수, 테스트 대상).
// 권한 판정은 호출자(Edge Function)가 담당. 여기서는 표시-안전 변환과 형식 검증만 한다.

import {
  capRegulationBody,
  normalizeRegulationFields,
  type RegulationField,
} from './regulation.ts';

// 카드에 노출할 요강 라벨:값 최대 개수 (카드가 과도하게 길어지지 않도록).
const MAX_CARD_REGULATION_FIELDS = 3;

export interface TournamentCardRow {
  id: string;
  sport: 'tennis' | 'futsal';
  title: string;
  start_date: string;
  end_date: string | null;
  application_deadline: string | null;
  region: string | null;
  location: string | null;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
  // 요강(migration 077/078): jsonb 라서 unknown 으로 받아 buildTournamentCards 에서 narrow.
  regulation_fields?: unknown;
}

export interface TournamentCardItem {
  id: string;
  title: string;
  sport: 'tennis' | 'futsal';
  region: string | null;
  location: string | null;
  start_date: string;
  end_date: string | null;
  application_deadline: string | null;
  eligible: boolean;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
  // 프론트 카드(chat_tournament_card.dart)가 렌더하는 요강 요약 (최대 3개).
  regulation_fields: RegulationField[];
}

export interface DateRange {
  from: string;
  to: string;
}

export interface TournamentSearchTextContext {
  sport?: 'tennis' | 'futsal' | null;
  region: string | null;
  dateRange?: DateRange;
  // chat 경로는 항상 내 등급 기준으로 필터링한다(p_only_my_grade=true).
  // 사용자가 조건을 인지하고 취소·재질문할 수 있도록 응답에 노출한다.
  onlyMyGrade?: boolean;
}

const MAX_CARDS = 10;

/// `tournament_search_by_slots`(only_my_grade=true) 결과를 카드 아이템으로 변환.
/// 그 RPC는 참가 가능한 대회만 반환하므로 eligible=true 로 표기한다.
export function buildTournamentCards(rows: TournamentCardRow[]): TournamentCardItem[] {
  return rows.slice(0, MAX_CARDS).map((r) => ({
    id: r.id,
    title: r.title,
    sport: r.sport,
    region: r.region,
    location: r.location,
    start_date: r.start_date,
    end_date: r.end_date,
    application_deadline: r.application_deadline ?? null,
    eligible: true,
    eligible_grades: r.eligible_grades ?? [],
    entry_fee: r.entry_fee,
    format: r.format,
    // 요강 jsonb → RegulationField[] narrow 후 상위 3개만 카드에 노출.
    regulation_fields: normalizeRegulationFields(r.regulation_fields).slice(
      0,
      MAX_CARD_REGULATION_FIELDS,
    ),
  }));
}

function tournamentSportLabel(sport: TournamentSearchTextContext['sport']): string {
  if (sport === 'tennis') return '테니스 대회';
  if (sport === 'futsal') return '풋살 대회';
  return '대회';
}

function tournamentSportHeading(sport: TournamentSearchTextContext['sport']): string {
  if (sport === 'tennis') return '🎾 테니스';
  if (sport === 'futsal') return '⚽ 풋살';
  return '대회';
}

function filterText(ctx: TournamentSearchTextContext): string {
  const filters: string[] = [];
  if (ctx.region) filters.push(ctx.region);
  if (ctx.dateRange) filters.push(`${ctx.dateRange.from} ~ ${ctx.dateRange.to}`);
  if (ctx.onlyMyGrade) filters.push('내 등급 기준');
  return filters.length > 0 ? ` (${filters.join(', ')})` : '';
}

export function renderTournamentSearchText(
  rows: TournamentCardRow[],
  ctx: TournamentSearchTextContext,
): string {
  const heading = tournamentSportHeading(ctx.sport);
  return [
    `## ${heading} ${rows.length}건${filterText(ctx)}`,
    '',
    '조건에 맞는 대회를 찾았습니다. 아래 카드에서 일정을 확인하고 필요한 항목을 선택해 주세요.',
  ].join('\n');
}

export function renderTournamentSearchEmptyText(ctx: TournamentSearchTextContext): string {
  const label = tournamentSportLabel(ctx.sport);
  const lines = [`조건에 맞는 ${label}가 없습니다${filterText(ctx)}.`];
  if (ctx.onlyMyGrade) {
    lines.push('지금은 내 등급에 참가 가능한 대회만 찾았어요.');
  }
  lines.push('기간·종목·지역을 바꿔서 다시 물어보거나 협회 공식 홈페이지를 확인해 주세요.');
  return lines.join('\n');
}

// ==========================================================================
// Tournament detail (selected_entity tournament / tournament_detail 라우팅)
// ==========================================================================

// 상세 응답 본문 길이 제한 (채팅 말풍선 과대 방지).
const DETAIL_BODY_CAP = 1200;

export interface TournamentDetailRow extends TournamentCardRow {
  organizer: string | null;
  prize: string | null;
  regulation_body: string | null;
  regulation_notes: string[] | null;
  source_url: string | null;
}

/// selected_entity(tournament) 카드 '상세 보기' 의 결정적(LLM 미사용) 마크다운 응답.
export function renderTournamentDetailText(row: TournamentDetailRow): string {
  const lines: string[] = [`## ${row.title}`, ''];

  const period = row.end_date && row.end_date !== row.start_date
    ? `${row.start_date} ~ ${row.end_date}`
    : row.start_date;
  lines.push(`- 일정: ${period}`);

  const place = [row.region, row.location].filter(Boolean).join(' ');
  if (place) lines.push(`- 장소: ${place}`);
  if (row.application_deadline) lines.push(`- 접수 마감: ${row.application_deadline}`);
  if (row.entry_fee !== null && row.entry_fee !== undefined) {
    lines.push(`- 참가비: ${row.entry_fee.toLocaleString('ko-KR')}원`);
  }
  if (row.format) lines.push(`- 경기 방식: ${row.format}`);
  if (row.organizer) lines.push(`- 주최: ${row.organizer}`);
  if (row.prize) lines.push(`- 시상: ${row.prize}`);

  const fields = normalizeRegulationFields(row.regulation_fields);
  if (fields.length > 0) {
    lines.push('', '### 요강');
    for (const f of fields) lines.push(`- ${f.label}: ${f.value}`);
  }

  const body = capRegulationBody(row.regulation_body, DETAIL_BODY_CAP);
  if (body) lines.push('', '### 요강 안내', body);

  const notes = (row.regulation_notes ?? []).filter((n) => n.trim().length > 0);
  if (notes.length > 0) {
    lines.push('');
    for (const n of notes) lines.push(`※ ${n}`);
  }

  // source_url 은 크롤러가 넣은 신뢰 불가 값 → http(s) 스킴만 링크로, 그 외는 무시.
  if (row.source_url && /^https?:\/\//i.test(row.source_url.trim())) {
    lines.push('', `[공식 페이지에서 보기](${row.source_url.trim()})`);
  }
  return lines.join('\n');
}

/// tournament_detail 의도 라우팅용 소개 문구.
/// 검색과 동일한 카드 목록을 붙이되, 신청 정보는 카드/상세 보기로 유도한다.
export function renderTournamentDetailIntroText(
  rows: TournamentCardRow[],
  ctx: TournamentSearchTextContext,
): string {
  const heading = tournamentSportHeading(ctx.sport);
  return [
    `## ${heading} ${rows.length}건${filterText(ctx)}`,
    '',
    '신청 정보(마감일·참가비·요강)는 아래 카드에서 확인할 수 있어요. ' +
    "특정 대회의 자세한 신청 방법은 카드의 '상세 보기'를 눌러주세요.",
  ].join('\n');
}

// ==========================================================================
// Club cards (club_search 라우팅 + selected_entity club 상세)
// ==========================================================================

export interface ClubCardRow {
  id: string;
  sport: 'tennis' | 'futsal';
  name: string;
  region: string | null;
  description: string | null;
  member_count: number;
  monthly_fee: number | null;
  meeting_days: string[];
  gender_preference: string | null;
}

/// 프론트와 계약된 카드 스키마 — 필드 추가/변경 시 앱 클럽 카드 위젯과 동기화 필요.
export interface ClubCardItem {
  id: string;
  name: string;
  sport: 'tennis' | 'futsal';
  region: string | null;
  description: string | null;
  member_count: number;
  monthly_fee: number | null;
  meeting_days: string[];
  gender_preference: string | null;
}

export function buildClubCards(rows: ClubCardRow[]): ClubCardItem[] {
  return rows.slice(0, MAX_CARDS).map((r) => ({
    id: r.id,
    name: r.name,
    sport: r.sport,
    region: r.region,
    description: r.description,
    member_count: r.member_count ?? 0,
    monthly_fee: r.monthly_fee,
    meeting_days: r.meeting_days ?? [],
    gender_preference: r.gender_preference,
  }));
}

export interface ClubSearchTextContext {
  sport?: 'tennis' | 'futsal' | null;
  region: string | null;
}

function clubSportLabel(sport: ClubSearchTextContext['sport']): string {
  if (sport === 'tennis') return '테니스 클럽';
  if (sport === 'futsal') return '풋살 클럽';
  return '클럽';
}

function clubSportHeading(sport: ClubSearchTextContext['sport']): string {
  if (sport === 'tennis') return '🎾 테니스 클럽';
  if (sport === 'futsal') return '⚽ 풋살 클럽';
  return '클럽';
}

function clubFilterText(ctx: ClubSearchTextContext): string {
  return ctx.region ? ` (${ctx.region})` : '';
}

export function renderClubSearchText(rows: ClubCardRow[], ctx: ClubSearchTextContext): string {
  return [
    `## ${clubSportHeading(ctx.sport)} ${rows.length}건${clubFilterText(ctx)}`,
    '',
    '조건에 맞는 클럽을 찾았습니다. 아래 카드에서 모임 요일·회비를 확인하고 관심 있는 클럽을 선택해 주세요.',
  ].join('\n');
}

export function renderClubSearchEmptyText(ctx: ClubSearchTextContext): string {
  return [
    `조건에 맞는 ${clubSportLabel(ctx.sport)}이 없습니다${clubFilterText(ctx)}.`,
    '지역·종목을 바꿔서 다시 물어보거나 클럽 탭에서 전체 클럽을 둘러봐 주세요.',
  ].join('\n');
}

export interface ClubDetailRow extends ClubCardRow {
  address: string | null;
  contact: string | null;
}

const CLUB_GENDER_LABELS: Record<string, string> = {
  male: '남성',
  female: '여성',
  mixed: '혼성',
};

/// selected_entity(club) 카드 선택의 결정적(LLM 미사용) 마크다운 응답.
export function renderClubDetailText(club: ClubDetailRow): string {
  const lines: string[] = [`## ${club.name}`, ''];
  lines.push(`- 종목: ${club.sport === 'tennis' ? '테니스' : '풋살'}`);
  if (club.region) lines.push(`- 지역: ${club.region}`);
  if (club.address) lines.push(`- 주소: ${club.address}`);
  const days = club.meeting_days ?? [];
  if (days.length > 0) lines.push(`- 정기 모임: ${days.join(', ')}`);
  if (club.monthly_fee !== null && club.monthly_fee !== undefined) {
    lines.push(`- 월 회비: ${club.monthly_fee.toLocaleString('ko-KR')}원`);
  }
  lines.push(`- 멤버: ${club.member_count ?? 0}명`);
  if (club.gender_preference) {
    lines.push(
      `- 성별: ${CLUB_GENDER_LABELS[club.gender_preference] ?? club.gender_preference}`,
    );
  }
  if (club.contact) lines.push(`- 연락처: ${club.contact}`);
  if (club.description) lines.push('', club.description);
  return lines.join('\n');
}

export type SelectedEntityType = 'tournament' | 'club';

export interface SelectedEntity {
  type: SelectedEntityType;
  id: string;
}

export type ParseResult<T> = { ok: true; value: T } | { ok: false };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VALID_ENTITY_TYPES: readonly SelectedEntityType[] = ['tournament', 'club'];

/// 신뢰할 수 없는 입력에서 selected_entity 를 검증한다.
/// 잘못된 타입이나 UUID 형식이 아닌 id 는 거부한다.
export function parseSelectedEntity(input: unknown): ParseResult<SelectedEntity> {
  if (input === null || typeof input !== 'object') return { ok: false };
  const obj = input as Record<string, unknown>;
  const type = obj.type;
  const id = obj.id;
  if (typeof type !== 'string' || typeof id !== 'string') return { ok: false };
  if (!VALID_ENTITY_TYPES.includes(type as SelectedEntityType)) return { ok: false };
  if (!UUID_RE.test(id)) return { ok: false };
  return { ok: true, value: { type: type as SelectedEntityType, id } };
}
