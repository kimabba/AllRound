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

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};

export function playerHistoryUrl(
  base: string,
  orgPlayerId: string,
  page: number,
): string {
  return `${base.replace(/\/+$/, '')}/sub4_6_rank.php?userid=${
    encodeURIComponent(orgPlayerId)
  }&page=${page}`;
}

// 한 선수의 이력은 페이지당 15행으로 잘려 온다(실측 2026-08-04). 한 페이지만 긁으면
// 최근 15건만 들어와 "과거가 즉시 채워진다"는 이 기능의 전제가 깨진다.
// 범위를 넘긴 페이지는 0행을 주므로(page=5·99 실측) 그걸 중단 조건으로 쓴다.
// 상한은 폭주 방지용이다 — 46행짜리 선수가 4페이지였으니 20이면 300행까지 커버한다.
const MAX_HISTORY_PAGES = 20;

/** 이 파일이 DB 에 요구하는 최소 형태. supabase-js 클라이언트가 이걸 만족한다. */
export interface SupabaseLike {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        eq(column: string, value: string): PromiseLike<
          { data: { org_player_id: string }[] | null; error: { message: string } | null }
        >;
      };
    };
  };
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ error: { message: string } | null }>;
}

/**
 * 연결 승인(confirmed)된 선수의 대회 이력을 수집한다.
 * 요청 수 = 승인자 수. 승인자가 없으면 요청 0건으로 즉시 끝난다.
 * 한 명이 실패해도 나머지는 계속한다 — 실패는 메시지로 모아 돌려준다.
 */
export async function crawlPlayerHistories(
  db: SupabaseLike,
  org: string,
  base: string,
): Promise<string[]> {
  const failures: string[] = [];

  const { data: links, error } = await db
    .from('org_player_links')
    .select('org_player_id')
    .eq('org_code', org)
    .eq('status', 'confirmed');

  if (error) return [`연결 목록 조회 실패: ${error.message}`];
  if (!links || links.length === 0) return failures;

  for (const link of links) {
    // 페이지를 끝까지 모은다. 0행이 나오면 그 페이지가 범위 밖이다.
    const rows: PlayerHistoryRow[] = [];
    let pageFailed = false;

    for (let page = 1; page <= MAX_HISTORY_PAGES; page++) {
      const url = playerHistoryUrl(base, link.org_player_id, page);
      let html: string;
      try {
        const res = await fetch(url, { headers: COMMON_HEADERS });
        if (!res.ok) {
          failures.push(`이력 ${link.org_player_id} p${page}: HTTP ${res.status}`);
          pageFailed = true;
          break;
        }
        html = await res.text();
      } catch (e) {
        failures.push(
          `이력 ${link.org_player_id} p${page}: ${e instanceof Error ? e.message : String(e)}`,
        );
        pageFailed = true;
        break;
      }

      const pageRows = parsePlayerHistoryRows(html);
      if (pageRows.length === 0) break; // 범위 밖 — 여기서 끝
      rows.push(...pageRows);
    }

    // 중간 페이지에서 실패하면 그 선수는 이번 회차를 통째로 건너뛴다.
    // 부분 적재는 upsert 라 데이터를 지우진 않지만, "몇 페이지까지 받았나"를
    // 알 수 없는 채로 남는 것보다 다음 크롤에 온전히 받는 편이 낫다.
    if (pageFailed) continue;

    // 0행은 실패가 아니다 — 아직 출전 이력이 없는 선수가 있다.
    if (rows.length === 0) continue;

    const { error: rpcErr } = await db.rpc('upsert_org_player_results', {
      p_org: org,
      p_org_player_id: link.org_player_id,
      p_rows: rows.map((r) => ({
        tournament_name: r.tournamentName,
        played_on: r.playedOn,
        event_raw: r.eventRaw,
        result_raw: r.resultRaw,
        result_round: r.resultRound,
        points: r.points,
      })),
    });
    if (rpcErr) failures.push(`이력 ${link.org_player_id}: upsert ${rpcErr.message}`);
  }

  return failures;
}
