// Chat a2ui 카드 빌더 + selected_entity 검증 (순수 함수, 테스트 대상).
// 권한 판정은 호출자(Edge Function)가 담당. 여기서는 표시-안전 변환과 형식 검증만 한다.

import { normalizeRegulationFields, type RegulationField } from './regulation.ts';
import { isValidSport, type Sport, SPORT_LABELS } from './enums.ts';

// 카드에 노출할 요강 라벨:값 최대 개수 (카드가 과도하게 길어지지 않도록).
const MAX_CARD_REGULATION_FIELDS = 3;

export interface TournamentCardRow {
  id: string;
  sport: Sport;
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
  sport: Sport;
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

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function isTournamentCardRow(value: unknown): value is TournamentCardRow {
  if (!isRecord(value)) return false;

  return typeof value.id === 'string' &&
    isValidSport(value.sport) &&
    typeof value.title === 'string' &&
    typeof value.start_date === 'string' &&
    (typeof value.end_date === 'string' || value.end_date === null) &&
    (typeof value.application_deadline === 'string' || value.application_deadline === null) &&
    (typeof value.region === 'string' || value.region === null) &&
    (typeof value.location === 'string' || value.location === null) &&
    isStringArray(value.eligible_grades) &&
    (typeof value.entry_fee === 'number' || value.entry_fee === null) &&
    (typeof value.format === 'string' || value.format === null);
}

export interface DateRange {
  from: string;
  to: string;
}

export interface TournamentSearchTextContext {
  sport?: Sport | null;
  region: string | null;
  dateRange?: DateRange;
}

const MAX_CARDS = 10;

/// `tournament_search_by_slots` 결과를 카드 아이템으로 변환.
/// eligible 은 호출자가 필터 상태로 넘긴다: only_my_grade=true(참가 가능 대회만
/// 반환) 면 true, 전체 검색(false)이면 자격을 알 수 없으므로 false 로 배지 숨김(JY-101).
export function buildTournamentCards(
  rows: TournamentCardRow[],
  eligible = true,
): TournamentCardItem[] {
  return rows.slice(0, MAX_CARDS).map((r) => ({
    id: r.id,
    title: r.title,
    sport: r.sport,
    region: r.region,
    location: r.location,
    start_date: r.start_date,
    end_date: r.end_date,
    application_deadline: r.application_deadline ?? null,
    eligible,
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

// 종목 이모지는 이 파일(채팅 텍스트 렌더)에서만 쓴다. Record<Sport, …> 라 종목이
// 늘면 타입 에러로 빠뜨릴 수 없다.
const SPORT_EMOJI: Record<Sport, string> = {
  tennis: '🎾',
  futsal: '⚽',
};

/** '테니스 대회' — 종목 미지정이면 명사만. */
function sportNoun(sport: Sport | null | undefined, noun: string): string {
  return sport ? `${SPORT_LABELS[sport]} ${noun}` : noun;
}

/** '🎾 테니스 클럽' — 종목 미지정이면 fallback. */
function sportHeadingWith(
  sport: Sport | null | undefined,
  noun: string,
  fallback: string,
): string {
  if (!sport) return fallback;
  const base = `${SPORT_EMOJI[sport]} ${SPORT_LABELS[sport]}`;
  return noun ? `${base} ${noun}` : base;
}

function tournamentSportLabel(sport: TournamentSearchTextContext['sport']): string {
  return sportNoun(sport, '대회');
}

function tournamentSportHeading(sport: TournamentSearchTextContext['sport']): string {
  return sportHeadingWith(sport, '', '대회');
}

function filterText(ctx: TournamentSearchTextContext): string {
  const filters: string[] = [];
  if (ctx.region) filters.push(ctx.region);
  if (ctx.dateRange) filters.push(`${ctx.dateRange.from} ~ ${ctx.dateRange.to}`);
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
  return [
    `조건에 맞는 ${label}가 없습니다${filterText(ctx)}.`,
    '기간, 종목, 등급 조건을 바꾸거나 협회 공식 홈페이지를 확인해 주세요.',
  ].join('\n');
}

export function renderTournamentApplicationGuideText(
  rows: TournamentCardRow[],
  ctx: TournamentSearchTextContext,
): string {
  const label = tournamentSportLabel(ctx.sport);
  if (rows.length === 0) {
    return [
      `현재 신청 가능한 ${label}가 없습니다${filterText(ctx)}.`,
      '대회 탭에서 기간·지역·등급 조건을 바꾸어 다시 확인하거나, 협회 공식 홈페이지의 접수 공지를 확인해 주세요.',
    ].join('\n');
  }

  return [
    `현재 신청 가능한 ${label} ${rows.length}건을 찾았습니다${filterText(ctx)}.`,
    '',
    '아래 카드에서 대회를 선택한 뒤 상세 요강과 원본 링크를 확인해 주세요. 접수는 대회마다 협회 홈페이지, 네이버 폼, 현장 접수 등 방식이 다를 수 있습니다.',
  ].join('\n');
}

// ==========================================================================
// Club cards (club_search 라우팅 + selected_entity club 상세)
// ==========================================================================

export interface ClubCardRow {
  id: string;
  sport: Sport;
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
  sport: Sport;
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
  sport?: Sport | null;
  region: string | null;
}

function clubSportLabel(sport: ClubSearchTextContext['sport']): string {
  return sportNoun(sport, '클럽');
}

function clubSportHeading(sport: ClubSearchTextContext['sport']): string {
  return sportHeadingWith(sport, '클럽', '클럽');
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
  lines.push(`- 종목: ${SPORT_LABELS[club.sport]}`);
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

// ── 대회검색 "내 등급만 보기"/"전체 보기" 정제 칩 (JY-101) ────────────────
// 전체 결과를 기본으로 보여주고, 등급 등록자에게만 반대 방향으로 좁히거나 넓히는
// 칩 하나를 카드에 붙인다. 칩 탭 시 이 refine 페이로드로 재요청 → intent 분류를
// 건너뛰고 같은 슬롯으로 only_my_grade 만 바꿔 재검색한다.

export interface TournamentRefine {
  sport: Sport | null;
  region_code: string | null;
  date_from: string | null;
  date_to: string | null;
  only_my_grade: boolean;
}

export interface RefineChip {
  label: string;
  refine: TournamentRefine;
}

/// 신뢰할 수 없는 입력에서 tournament_refine 페이로드를 검증한다.
export function parseTournamentRefine(input: unknown): ParseResult<TournamentRefine> {
  if (!isRecord(input)) return { ok: false };
  const onlyMyGrade = input.only_my_grade;
  if (typeof onlyMyGrade !== 'boolean') return { ok: false };
  const sport = input.sport;
  if (sport !== 'tennis' && sport !== 'futsal' && sport !== null && sport !== undefined) {
    return { ok: false };
  }
  const strOrNull = (v: unknown): string | null => (typeof v === 'string' ? v : null);
  // date 는 PG date 파라미터로 나가므로 ISO(YYYY-MM-DD) 만 통과시킨다. 형식이
  // 아니거나 from>to 로 뒤집힌 조작 payload 는 날짜 필터를 떨궈 RPC 에러를 막는다.
  const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
  const isoDateOrNull = (v: unknown): string | null =>
    typeof v === 'string' && ISO_DATE_RE.test(v) ? v : null;
  let dateFrom = isoDateOrNull(input.date_from);
  let dateTo = isoDateOrNull(input.date_to);
  if (dateFrom && dateTo && dateFrom > dateTo) {
    dateFrom = null;
    dateTo = null;
  }
  return {
    ok: true,
    value: {
      sport: (sport as Sport | null) ?? null,
      region_code: strOrNull(input.region_code),
      date_from: dateFrom,
      date_to: dateTo,
      only_my_grade: onlyMyGrade,
    },
  };
}

/// 현재 검색이 only_my_grade 였는지에 따라 반대 방향 칩 하나를 만든다.
/// 전체(false) → "내 등급만 보기", 내 등급(true) → "전체 대회 보기".
export function buildRefineChip(
  currentOnlyMyGrade: boolean,
  slots: Omit<TournamentRefine, 'only_my_grade'>,
): RefineChip {
  const next = !currentOnlyMyGrade;
  return {
    label: next ? '내 등급만 보기' : '전체 대회 보기',
    refine: { ...slots, only_my_grade: next },
  };
}

/// 해당 종목에 등급/부서를 등록한 사용자인지. 미등록자에겐 정제 칩을 노출하지 않는다.
/// 테니스는 division_codes 가 채워진 소속이 있어야, 풋살은 grade 가 있어야 필터가 의미 있다.
export function isGradeRegisteredForSport(
  sport: Sport | null,
  tennisOrgs: ReadonlyArray<{ division_codes: string[] }>,
  futsalGrades: ReadonlyArray<string | null | undefined>,
): boolean {
  if (sport === 'tennis') {
    return tennisOrgs.some((o) => (o.division_codes?.length ?? 0) > 0);
  }
  if (sport === 'futsal') {
    return futsalGrades.some((g) => !!g);
  }
  return false;
}
