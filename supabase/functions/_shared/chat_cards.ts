// Chat a2ui 카드 빌더 + selected_entity 검증 (순수 함수, 테스트 대상).
// 권한 판정은 호출자(Edge Function)가 담당. 여기서는 표시-안전 변환과 형식 검증만 한다.

export interface TournamentCardRow {
  id: string;
  sport: 'tennis' | 'futsal';
  title: string;
  start_date: string;
  end_date: string | null;
  region: string | null;
  location: string | null;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
}

export interface TournamentCardItem {
  id: string;
  title: string;
  sport: 'tennis' | 'futsal';
  region: string | null;
  location: string | null;
  start_date: string;
  end_date: string | null;
  eligible: boolean;
  eligible_grades: string[];
  entry_fee: number | null;
  format: string | null;
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
    eligible: true,
    eligible_grades: r.eligible_grades ?? [],
    entry_fee: r.entry_fee,
    format: r.format,
  }));
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
