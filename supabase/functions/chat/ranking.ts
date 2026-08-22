import type { RankingDivisionCode, RankingOrgCode } from '../_shared/intent.ts';

/** `org_rankings`에서 챗 응답에 필요한 필드만 고른 행. */
export interface OrgRankingRow {
  org_code: RankingOrgCode;
  division_code: RankingDivisionCode;
  rank: number;
  player_name: string;
  org_player_id: string | null;
  club_raw: string | null;
  rank_points: number;
  total_points: number;
}

export interface RankingQueryLabels {
  orgCode?: RankingOrgCode;
  divisionCode?: RankingDivisionCode;
  playerName?: string;
}

const ORG_LABELS: Record<RankingOrgCode, string> = {
  gj: '광주광역시테니스협회',
  jn: '전라남도테니스협회',
};

const DIVISION_LABELS: Record<RankingDivisionCode, string> = {
  gj_m_gold: '골드부',
  gj_m_general: '남자일반부',
  gj_m_instructor: '지도자부',
  gj_w_rookie: '여자신인부',
  gj_w_gukhwa: '국화부',
  gj_w_geumbae: '여자금배부',
  jn_m_gold: '골드부',
  jn_m_general: '남자일반부',
  jn_m_instructor: '지도자부',
  jn_w_rookie: '여자신인부',
  jn_w_gukhwa: '국화부',
  jn_w_geumbae: '여자금배부',
};

const RANKING_DIVISION_CODES = new Set<RankingDivisionCode>(
  Object.keys(DIVISION_LABELS) as RankingDivisionCode[],
);
const POINT_FORMATTER = new Intl.NumberFormat('ko-KR');

/** 랭킹 출처·제목에서 내부 부서 코드 대신 사용자용 협회/부서명을 쓴다. */
export function rankingScopeLabel(
  orgCode: RankingOrgCode,
  divisionCode: RankingDivisionCode,
): string {
  return `${ORG_LABELS[orgCode]} ${DIVISION_LABELS[divisionCode]}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isRankingOrgCode(value: unknown): value is RankingOrgCode {
  return value === 'gj' || value === 'jn';
}

function isRankingDivisionCode(value: unknown): value is RankingDivisionCode {
  return typeof value === 'string' &&
    RANKING_DIVISION_CODES.has(value as RankingDivisionCode);
}

function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

function isPositiveInteger(value: unknown): value is number {
  return isNonNegativeInteger(value) && value > 0;
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === 'string';
}

function parseOrgRankingRow(value: unknown, index: number): OrgRankingRow {
  if (
    !isRecord(value) ||
    !isRankingOrgCode(value.org_code) ||
    !isRankingDivisionCode(value.division_code) ||
    !value.division_code.startsWith(`${value.org_code}_`) ||
    !isPositiveInteger(value.rank) ||
    typeof value.player_name !== 'string' ||
    value.player_name.trim().length === 0 ||
    !isNullableString(value.org_player_id) ||
    !isNullableString(value.club_raw) ||
    !isNonNegativeInteger(value.rank_points) ||
    !isNonNegativeInteger(value.total_points)
  ) {
    throw new TypeError(`org_rankings[${index}] 형식이 올바르지 않습니다`);
  }
  return {
    org_code: value.org_code,
    division_code: value.division_code,
    rank: value.rank,
    player_name: value.player_name.trim(),
    org_player_id: value.org_player_id,
    club_raw: value.club_raw,
    rank_points: value.rank_points,
    total_points: value.total_points,
  };
}

/** Supabase의 외부 JSON 경계에서 `org_rankings` 행을 즉시 좁힌다. */
export function parseOrgRankingRows(value: unknown): OrgRankingRow[] {
  if (!Array.isArray(value)) throw new TypeError('org_rankings 결과는 배열이어야 합니다');
  return value.map(parseOrgRankingRow);
}

function cleanClubName(clubRaw: string | null): string | null {
  if (clubRaw === null) return null;
  const cleaned = clubRaw.trim().replace(/\/+$/g, '');
  return cleaned.length > 0 ? cleaned : null;
}

function tieKey(row: OrgRankingRow): string {
  return `${row.org_code}:${row.division_code}:${row.rank}`;
}

function renderRows(rows: readonly OrgRankingRow[]): string[] {
  const tieCounts = new Map<string, number>();
  for (const row of rows) tieCounts.set(tieKey(row), (tieCounts.get(tieKey(row)) ?? 0) + 1);

  return [...rows]
    .sort((a, b) =>
      a.org_code.localeCompare(b.org_code) ||
      a.division_code.localeCompare(b.division_code) ||
      a.rank - b.rank ||
      a.player_name.localeCompare(b.player_name, 'ko')
    )
    .map((row) => {
      const rankLabel = `${(tieCounts.get(tieKey(row)) ?? 0) > 1 ? '공동 ' : ''}${row.rank}위`;
      const club = cleanClubName(row.club_raw);
      const player = club ? `${row.player_name} (${club})` : row.player_name;
      return `- ${rankLabel} ${player} · 순위포인트 ${
        POINT_FORMATTER.format(row.rank_points)
      }점 · 전체포인트 ${POINT_FORMATTER.format(row.total_points)}점`;
    });
}

function queryLabel(query: RankingQueryLabels): string {
  const labels: string[] = [];
  if (query.orgCode) labels.push(ORG_LABELS[query.orgCode]);
  if (query.divisionCode) labels.push(DIVISION_LABELS[query.divisionCode]);
  if (query.playerName) labels.push(`${query.playerName} 선수`);
  return labels.join(' ');
}

/** 일반 협회 랭킹 조회 결과를 LLM 없이 사용자용 한국어로 렌더한다. */
export function renderRankingResults(
  rows: readonly OrgRankingRow[],
  query: RankingQueryLabels = {},
): string {
  const label = queryLabel(query);
  if (rows.length === 0) {
    return label
      ? `${label}의 현재 랭킹 결과가 없습니다.`
      : '조건에 맞는 현재 협회 랭킹 결과가 없습니다.';
  }

  const inferredLabel = label || queryLabel({
    orgCode: rows[0].org_code,
    divisionCode: rows.every((row) => row.division_code === rows[0].division_code)
      ? rows[0].division_code
      : undefined,
  });
  return [`${inferredLabel} 현재 랭킹입니다.`, ...renderRows(rows)].join('\n');
}
