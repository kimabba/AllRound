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
const TH_RE = /<th\b[^>]*>([\s\S]*?)<\/th>/gi;

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
 * 표 헤더에 이 페이지의 컬럼명이 있는지 판정한다.
 *
 * 이력이 0건인 선수도 표 헤더(<th>대회명·순위·종목·포인트·대회일)는 그대로 나온다
 * (실측 2026-08-04) — "아직 이력 없음"(정상)과 "에러/차단/로그인 페이지·레이아웃 변경"
 * (실패)을 가르는 신호로 쓴다. 문구가 통째로 바뀌면 이것도 깨지므로 헤더 전체가 아니라
 * 핵심 단어 몇 개만 본다(과한 매칭 금지).
 */
export function looksLikeHistoryPage(html: string): boolean {
  const headers: string[] = [];
  TH_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = TH_RE.exec(html)) !== null) {
    headers.push(textOf(m[1]));
  }
  const need = ['대회명', '순위', '대회일'];
  return need.every((k) => headers.some((h) => h.includes(k)));
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

/**
 * 같은 (대회명, 대회일) 중복 행을 하나로 줄인다. 나중 행이 이긴다.
 *
 * 실측(2026-08-19, gjtennis.kr userid=nujani): 협회 원본이 같은 대회명+날짜를
 * 부서만 다르게(예: 남자단체전) 여러 번 반복해서 준다. upsert_org_player_results
 * 의 ON CONFLICT 대상이 (org_code, org_player_id, tournament_name, played_on)
 * 라 event_raw(부서)는 안 걸린다 — 한 INSERT 문 안에서 같은 대상을 두 번 이상
 * 건드리면 Postgres 가 "ON CONFLICT DO UPDATE command cannot affect row a
 * second time" 로 문장 전체를 롤백해, 그 선수의 전적이 하나도 안 쌓인다.
 */
export function dedupeHistoryRows(rows: PlayerHistoryRow[]): PlayerHistoryRow[] {
  const byKey = new Map<string, PlayerHistoryRow>();
  for (const r of rows) {
    byKey.set(`${r.tournamentName} ${r.playedOn}`, r);
  }
  return [...byKey.values()];
}

export interface RankingTotal {
  orgPlayerId: string;
  totalPoints: number;
}

export interface HistoryCrawlStateRow {
  orgPlayerId: string;
  lastPoints: number;
  lastCrawledAt: string;
}

/**
 * 이번 회차에 개인 이력을 크롤할 선수 목록을 정한다.
 *
 * confirmed 연결자는 상한과 무관하게 항상 포함된다("내 기록" 화면이 직접
 * 의존하므로 놓치면 안 된다). 나머지는 org_rankings 의 total_points 가 state 의
 * last_points 와 다르거나(변경) state 가 아예 없으면(신규) 후보가 되고, cap 을
 * 넘는 만큼은 이번 회차에서 빠진다 — last_crawled_at 이 오래된(또는 아예 없는)
 * 순으로 우선권을 줘서, 상한에 밀린 선수가 다음 회차에 먼저 뽑히게 한다.
 */
export function selectHistoryCandidates(params: {
  confirmedOrgPlayerIds: string[];
  rankings: RankingTotal[];
  state: HistoryCrawlStateRow[];
  cap: number;
}): string[] {
  const { confirmedOrgPlayerIds, rankings, state, cap } = params;
  const confirmed = new Set(confirmedOrgPlayerIds);
  const stateByPlayer = new Map(state.map((s) => [s.orgPlayerId, s]));

  const eligible = rankings.filter((r) => {
    if (confirmed.has(r.orgPlayerId)) return false; // 이미 항상 포함되므로 중복 방지
    const s = stateByPlayer.get(r.orgPlayerId);
    return !s || s.lastPoints !== r.totalPoints;
  });

  eligible.sort((a, b) => {
    const aAt = stateByPlayer.get(a.orgPlayerId)?.lastCrawledAt ?? '';
    const bAt = stateByPlayer.get(b.orgPlayerId)?.lastCrawledAt ?? '';
    if (aAt !== bAt) return aAt < bAt ? -1 : 1;
    return a.orgPlayerId < b.orgPlayerId ? -1 : 1;
  });

  const capped = eligible.slice(0, cap).map((r) => r.orgPlayerId);
  return [...confirmedOrgPlayerIds, ...capped];
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

// 회차당 크롤 인원 상한. 상한을 넘는 변경분/신규 후보는 이번 회차에 빠지고
// last_crawled_at 이 갱신되지 않아 다음 회차에 자연히 우선권을 갖는다(§2 결정3).
// 잘못된/빈 환경변수는 NaN 이 될 수 있어 후보가 조용히 0명이 되는 걸 막는다.
// 배포 후 crawl_audit 의 started_at~finished_at 실측으로 기본값을 튜닝할 것.
const parsedHistoryCap = Number(Deno.env.get('ORG_PLAYER_HISTORY_CAP'));
export const HISTORY_CANDIDATE_CAP = Number.isFinite(parsedHistoryCap) && parsedHistoryCap > 0
  ? parsedHistoryCap
  : 100;

// 요청량이 확 늘어나므로(연결자 소수 → 전 선수) 협회 사이트에 대한 예의 차원의 딜레이.
const REQUEST_DELAY_MS = 150;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// PostgREST 기본 응답 상한(1,000행) 회피용 페이지네이션. org_rankings 가
// gj 1,709 / jn 1,837 명이라 한 번에 안 긁으면 뒤쪽 선수가 조용히 잘린다.
export async function fetchAllRows<T>(
  fetchPage: (
    from: number,
    to: number,
  ) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  pageSize: number,
): Promise<{ rows: T[]; error: string | null }> {
  const rows: T[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await fetchPage(from, from + pageSize - 1);
    if (error) return { rows, error: error.message };
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
    from += pageSize;
  }
  return { rows, error: null };
}

const SUPABASE_PAGE_SIZE = 1000;

export interface PlayerHistoryFetchResult {
  rows: PlayerHistoryRow[];
  reachedPageLimit: boolean;
}

/**
 * 협회 선수 한 명의 이력을 끝 페이지까지 가져온다.
 *
 * UI 온디맨드 조회와 정기 크롤러가 같은 페이지 종료·레이아웃 검증 규칙을 써야
 * 한쪽만 조용히 일부 이력을 누락하는 일이 없다.
 */
export async function fetchPlayerHistory(
  base: string,
  orgPlayerId: string,
  pageDelayMs = 0,
): Promise<PlayerHistoryFetchResult> {
  const rows: PlayerHistoryRow[] = [];

  for (let page = 1; page <= MAX_HISTORY_PAGES; page++) {
    const url = playerHistoryUrl(base, orgPlayerId, page);
    let html: string;
    try {
      const res = await fetch(url, { headers: COMMON_HEADERS });
      if (!res.ok) throw new Error(`p${page}: HTTP ${res.status}`);
      html = await res.text();
      if (pageDelayMs > 0) await sleep(pageDelayMs);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      throw new Error(message.startsWith(`p${page}:`) ? message : `p${page}: ${message}`);
    }

    const pageRows = parsePlayerHistoryRows(html);
    if (pageRows.length === 0) {
      if (!looksLikeHistoryPage(html)) {
        throw new Error(`p${page}: 0행, 표 헤더 없음 — 레이아웃 변경 의심`);
      }
      return { rows, reachedPageLimit: false };
    }
    rows.push(...pageRows);
  }

  return { rows, reachedPageLimit: true };
}

/** 이 파일이 DB 에 요구하는 최소 형태. supabase-js 클라이언트가 이걸 만족한다. */
export interface SupabaseLike {
  from(table: 'org_player_links'): {
    select(columns: string): {
      eq(column: string, value: string): {
        eq(column: string, value: string): PromiseLike<
          { data: { org_player_id: string }[] | null; error: { message: string } | null }
        >;
      };
    };
  };
  from(table: 'org_rankings'): {
    select(columns: string): {
      eq(column: string, value: string): {
        range(from: number, to: number): PromiseLike<
          {
            data: { org_player_id: string | null; total_points: number }[] | null;
            error: { message: string } | null;
          }
        >;
      };
    };
  };
  from(table: 'org_player_history_crawl_state'): {
    select(columns: string): {
      eq(column: string, value: string): {
        range(from: number, to: number): PromiseLike<
          {
            data:
              | { org_player_id: string; last_points: number; last_crawled_at: string }[]
              | null;
            error: { message: string } | null;
          }
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
 * 개인 이력 크롤 대상: confirmed 연결자(항상) + 랭킹표 기준 변경분/신규(상한 적용).
 * 상한에 걸려 밀린 후보는 상태가 안 갱신되므로 다음 회차에 자연히 다시 후보가 된다.
 * 한 명이 실패해도 나머지는 계속한다 — 실패는 메시지로 모아 돌려준다.
 */
export async function crawlPlayerHistories(
  db: SupabaseLike,
  org: string,
  base: string,
): Promise<string[]> {
  const failures: string[] = [];

  let confirmedLinks: { org_player_id: string }[] | null;
  try {
    const { data, error } = await db
      .from('org_player_links')
      .select('org_player_id')
      .eq('org_code', org)
      .eq('status', 'confirmed');
    if (error) return [`연결 목록 조회 실패: ${error.message}`];
    confirmedLinks = data;
  } catch (e) {
    // supabase-js 가 에러 객체 대신 예외를 던지는 경로 — 여기서 막지 않으면
    // 랭킹 파서 전체(gnuboardRankingParser)를 뚫고 나가 부서 교체까지 죽인다.
    return [`연결 목록 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  // org_rankings 는 gj 1,709 / jn 1,837명이라 PostgREST 기본 응답 상한(1,000행)을
  // 넘는다 — fetchAllRows 로 안 긁으면 뒤쪽 700~800여 명이 조용히 잘린다.
  let rankingRows: { org_player_id: string | null; total_points: number }[];
  try {
    const result = await fetchAllRows<{ org_player_id: string | null; total_points: number }>(
      (from, to) =>
        db.from('org_rankings').select('org_player_id, total_points').eq('org_code', org).range(
          from,
          to,
        ),
      SUPABASE_PAGE_SIZE,
    );
    if (result.error) return [`랭킹 조회 실패: ${result.error}`];
    rankingRows = result.rows;
  } catch (e) {
    return [`랭킹 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  let stateRows: { org_player_id: string; last_points: number; last_crawled_at: string }[];
  try {
    const result = await fetchAllRows<
      { org_player_id: string; last_points: number; last_crawled_at: string }
    >(
      (from, to) =>
        db.from('org_player_history_crawl_state').select(
          'org_player_id, last_points, last_crawled_at',
        ).eq('org_code', org).range(from, to),
      SUPABASE_PAGE_SIZE,
    );
    if (result.error) return [`크롤 상태 조회 실패: ${result.error}`];
    stateRows = result.rows;
  } catch (e) {
    return [`크롤 상태 조회 예외: ${e instanceof Error ? e.message : String(e)}`];
  }

  const rankedRows = rankingRows.filter(
    (r): r is { org_player_id: string; total_points: number } => r.org_player_id != null,
  );
  const pointsByPlayer = new Map(rankedRows.map((r) => [r.org_player_id, r.total_points]));

  const candidateIds = selectHistoryCandidates({
    confirmedOrgPlayerIds: (confirmedLinks ?? []).map((l) => l.org_player_id),
    rankings: rankedRows.map((r) => ({
      orgPlayerId: r.org_player_id,
      totalPoints: r.total_points,
    })),
    state: stateRows.map((s) => ({
      orgPlayerId: s.org_player_id,
      lastPoints: s.last_points,
      lastCrawledAt: s.last_crawled_at,
    })),
    cap: HISTORY_CANDIDATE_CAP,
  });

  if (candidateIds.length === 0) return failures;

  for (const orgPlayerId of candidateIds) {
    // 페이지 fetch·종료·레이아웃 검증은 온디맨드 경로와 공유하는
    // fetchPlayerHistory 가 담당한다(#476). 크롤러만 페이지 간 딜레이를 준다.
    let fetched: PlayerHistoryFetchResult;
    try {
      fetched = await fetchPlayerHistory(base, orgPlayerId, REQUEST_DELAY_MS);
    } catch (e) {
      // 실패한 선수는 상태를 갱신하지 않아 다음 회차에 다시 후보로 잡힌다(§3.1).
      failures.push(
        `이력 ${orgPlayerId} ${e instanceof Error ? e.message : String(e)}`,
      );
      await sleep(REQUEST_DELAY_MS);
      continue;
    }

    // 상한까지 꽉 채우고 끝났다 — 데이터는 있는 만큼 적재하되(아래 계속) 잘렸다는
    // 사실을 알린다. 조용히 뒤쪽 이력이 사라지는 것보다 낫다.
    if (fetched.reachedPageLimit) {
      failures.push(
        `이력 ${orgPlayerId}: ${MAX_HISTORY_PAGES}페이지 상한 도달 — 이후 이력 잘림 가능`,
      );
    }

    // 0행은 그 자체로는 실패가 아니다 — 아직 출전 이력이 없는 선수가 있다.
    if (fetched.rows.length === 0) {
      await sleep(REQUEST_DELAY_MS);
      continue;
    }

    try {
      const { error: rpcErr } = await db.rpc('upsert_org_player_results', {
        p_org: org,
        p_org_player_id: orgPlayerId,
        p_rows: dedupeHistoryRows(fetched.rows).map((r) => ({
          tournament_name: r.tournamentName,
          played_on: r.playedOn,
          event_raw: r.eventRaw,
          result_raw: r.resultRaw,
          result_round: r.resultRound,
          points: r.points,
        })),
      });
      if (rpcErr) {
        failures.push(`이력 ${orgPlayerId}: upsert ${rpcErr.message}`);
      } else {
        // 성공한 선수만 상태를 갱신한다 — 실패한 선수는 손대지 않아 다음 회차에
        // 다시 후보로 잡히게 한다(§3.1). 현재 랭킹표에 없는 선수(탈퇴·랭킹 제외
        // 등)는 비교 기준(total_points)이 없어 기록하지 않는다.
        const currentPoints = pointsByPlayer.get(orgPlayerId);
        if (currentPoints !== undefined) {
          const { error: stateErr } = await db.rpc('record_org_player_history_crawl_state', {
            p_org: org,
            p_org_player_id: orgPlayerId,
            p_points: currentPoints,
          });
          if (stateErr) {
            failures.push(`이력 ${orgPlayerId}: 상태 기록 ${stateErr.message}`);
          }
        }
      }
    } catch (e) {
      // db.rpc 도 예외를 던질 수 있다 — 여기서 막아 랭킹 파서 전체가 죽지 않게 한다.
      failures.push(
        `이력 ${orgPlayerId}: upsert 예외 ${e instanceof Error ? e.message : String(e)}`,
      );
    }

    await sleep(REQUEST_DELAY_MS);
  }

  return failures;
}
