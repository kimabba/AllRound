// _shared/crawler/parsers/gnuboard_player_history.ts
//
// 협회 개인 대회 이력 parser.
//   URL: {base}/sub4_6_rank.php?userid={org_player_id}
//   컬럼: 대회명 | 순위 | 종목 | 포인트 | 대회일
//
// 랭킹표 parser 와 같은 이유로 DOM 을 만들지 않고 정규식으로 행 단위 스캔한다
// (deno-dom 은 WASM 힙에 트리를 올려 Edge 리소스 한도를 넘긴 실측이 있다).
//
// 주의: 여기 '순위'는 그 대회 진출 라운드(1=우승, 4=4강)이지 부서 내 랭킹 순위가 아니다.
//   표기가 '1'·'4'·'16' 과 '16강'·'4강'·'32강' 으로 섞여 온다(선행 설계 §2.2 실측).
//   못 읽으면 NULL 로 두고 원문을 남긴다 — 추측값으로 채우지 않는다.
//
// 설계: docs/superpowers/specs/2026-08-03-personal-record-history-design.md

const ROW_RE = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
const CELL_RE = /<td\b[^>]*>([\s\S]*?)<\/td>/gi;

const ENTITY_MAP: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  '#39': "'",
  nbsp: ' ',
};

function decodeEntities(s: string): string {
  return s.replace(/&(#39|amp|lt|gt|quot|nbsp);/g, (_, name: string) => ENTITY_MAP[name]);
}

function textOf(cellHtml: string): string {
  return decodeEntities(cellHtml.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

function toPoints(raw: string): number {
  const n = Number.parseInt(raw.replace(/[^0-9]/g, ''), 10);
  return Number.isNaN(n) ? 0 : n;
}

/**
 * 대회일 → 'YYYY-MM-DD'. 못 읽으면 null.
 *
 * 실측(2026-08-04): 협회는 **'2026년 7월 05일'** 형태로 준다. 숫자 사이 구분자가
 * 한글이라 `[.\-/]` 만으로는 한 행도 못 읽고 전부 조용히 버려진다.
 * 다른 표기로 바뀔 수 있어 구분자를 넓게 잡는다.
 */
function normalizeDate(raw: string): string | null {
  const m = raw.match(/(\d{4})\s*[년.\-/]\s*(\d{1,2})\s*[월.\-/]\s*(\d{1,2})/);
  if (!m) return null;
  const [, y, mo, d] = m;
  return `${y}-${mo.padStart(2, '0')}-${d.padStart(2, '0')}`;
}

/**
 * 진출 라운드 정규화. '1'→1, '16강'→16, '우승'→1, '준우승'→2.
 * 읽을 수 없으면 null — 0 이나 추측값으로 채우지 않는다.
 */
export function normalizeResultRound(raw: string): number | null {
  const s = raw.trim();
  if (s === '') return null;
  if (s.includes('준우승')) return 2;
  if (s.includes('우승')) return 1;
  const m = s.match(/^(\d+)\s*강?$/);
  if (!m) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isInteger(n) && n > 0 ? n : null;
}

export interface PlayerHistoryRow {
  tournamentName: string;
  playedOn: string; // 'YYYY-MM-DD'
  eventRaw: string | null;
  resultRaw: string;
  resultRound: number | null;
  points: number;
}

/** 개인 이력 HTML → 행 배열. 순수 함수(네트워크·DB 없음)라 테스트가 이것만 본다. */
export function parsePlayerHistoryRows(html: string): PlayerHistoryRow[] {
  const out: PlayerHistoryRow[] = [];

  ROW_RE.lastIndex = 0;
  let rowMatch: RegExpExecArray | null;
  while ((rowMatch = ROW_RE.exec(html)) !== null) {
    const cells: string[] = [];
    CELL_RE.lastIndex = 0;
    let cellMatch: RegExpExecArray | null;
    while ((cellMatch = CELL_RE.exec(rowMatch[1])) !== null) {
      cells.push(cellMatch[1]);
    }
    if (cells.length < 5) continue; // 헤더·안내 행

    const tournamentName = textOf(cells[0]);
    const playedOn = normalizeDate(textOf(cells[4]));
    // 대회명과 대회일이 없으면 유니크 키를 만들 수 없다 — 저장하지 않는다.
    if (!tournamentName || !playedOn) continue;

    const eventRaw = textOf(cells[2]);
    const resultRaw = textOf(cells[1]);

    out.push({
      tournamentName,
      playedOn,
      eventRaw: eventRaw === '' ? null : eventRaw,
      resultRaw,
      resultRound: normalizeResultRound(resultRaw),
      points: toPoints(textOf(cells[3])),
    });
  }
  return out;
}
