// Chat a2ui 카드 빌더 + selected_entity 검증 (순수 함수, 테스트 대상).
// 권한 판정은 호출자(Edge Function)가 담당. 여기서는 표시-안전 변환과 형식 검증만 한다.

import { normalizeRegulationFields, type RegulationField } from './regulation.ts';

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
