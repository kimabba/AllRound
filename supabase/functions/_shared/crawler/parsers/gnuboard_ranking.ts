// _shared/crawler/parsers/gnuboard_ranking.ts
//
// 광주·전남 협회 부서별 랭킹표 parser.
//   URL: {base}/sub4_5.php?member_kind={부서명}
//   광주(gjtennis.kr)·전남(jntennis.kr)이 동일 CMS 라 parser 하나로 둘 다 처리한다.
//
// 실측 구조(2026-08-03 확인):
//   <td data-table="wr_1">순위</td>
//   <td data-table="wr_2">부서</td>
//   <td data-table="wr_3"><a href="javascript:player_rank('아이디')"><img></a></td>
//   <td data-table="wr_4"><a href="javascript:player_rank('아이디','부서')"><b>성명</b></a></td>
//   <td data-table="wr_5">소속</td>
//   <td data-table="wr_6">순위포인트</td>
//   <td data-table="wr_6">전체포인트</td>   ← 같은 data-table 값. 순서로만 구분된다
//
// 규약:
//   - 0점 선수는 저장하지 않는다(개인정보 최소화). 순위는 협회 값을 그대로 쓰므로
//     0점 구간을 버려도 남는 행의 rank 가 깨지지 않는다.
//   - 개인 상세(sub4_6_rank.php)는 fetch 하지 않는다. 선수당 1요청 × 수천 명 방지 겸.
//   - 협회가 시즌·공표일을 주지 않으므로 부서 단위 delete+insert 로 현재상태만 유지한다.
//   - 앱은 점수를 계산하지 않는다. 협회 공표값을 그대로 옮긴다.
//
// 설계: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md

import { DOMParser } from 'deno-dom';
import { saveRawDocument } from '../../crawler.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};

/** 협회 랭킹표 member_kind → 부서 코드 접미사. 광주·전남 동일 7개. */
const MEMBER_KIND_SUFFIX: Record<string, string> = {
  '골드부': '_m_gold',
  '남자일반부': '_m_general',
  '남자신인부': '_m_rookie',
  '지도자부': '_m_instructor',
  '여자신인부': '_w_rookie',
  '국화부': '_w_gukhwa',
  '여자금배부': '_w_geumbae',
};

export interface RankingRow {
  rank: number;
  playerName: string;
  orgPlayerId: string | null;
  clubRaw: string | null;
  rankPoints: number;
  totalPoints: number;
}

type El = {
  getAttribute(name: string): string | null;
  textContent: string;
  querySelector(sel: string): El | null;
  querySelectorAll(sel: string): ArrayLike<El> & Iterable<El>;
};

/** '2,649' → 2649. 숫자가 아니면 0. */
function toPoints(raw: string): number {
  const n = Number.parseInt(raw.replace(/[^0-9]/g, ''), 10);
  return Number.isNaN(n) ? 0 : n;
}

/** javascript:player_rank('vudghk2116','골드부') → 'vudghk2116' */
function extractPlayerId(cell: El | null): string | null {
  if (!cell) return null;
  const anchor = cell.querySelector('a');
  const href = anchor?.getAttribute('href') ?? '';
  const m = href.match(/player_rank\(\s*'([^']+)'/);
  return m ? m[1] : null;
}

function textOf(cell: El | null): string {
  return (cell?.textContent ?? '').trim();
}

/**
 * 랭킹표 HTML → 행 배열. 순수 함수(네트워크·DB 접근 없음)라 테스트가 이것만 검증한다.
 * 0점 필터는 여기서 하지 않는다 — 호출자 책임.
 */
export function parseRankingRows(html: string): RankingRow[] {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  if (!doc) return [];

  const out: RankingRow[] = [];
  for (const tr of doc.querySelectorAll('tr') as unknown as Iterable<El>) {
    const cells = Array.from(tr.querySelectorAll('td') as unknown as Iterable<El>);
    if (cells.length < 7) continue; // 헤더 행(th) · 안내 행

    const rank = Number.parseInt(textOf(cells[0]).replace(/[^0-9]/g, ''), 10);
    if (!Number.isInteger(rank) || rank <= 0) continue;

    const nameCell = cells[3];
    const playerName = textOf(nameCell);
    if (!playerName) continue;

    const club = textOf(cells[4]);

    out.push({
      rank,
      playerName,
      // 성명 셀에서 뽑는다 — 사진이 없는 행은 wr_3 의 <a> 가 비어 있다
      orgPlayerId: extractPlayerId(nameCell) ?? extractPlayerId(cells[2]),
      clubRaw: club === '' ? null : club,
      // wr_6 이 두 번 나오므로 순서로 가른다
      rankPoints: toPoints(textOf(cells[5])),
      totalPoints: toPoints(textOf(cells[6])),
    });
  }
  return out;
}

/**
 * 한 협회의 랭킹 부서 7개를 순회해 org_rankings 를 부서 단위로 교체한다.
 * source.url 은 base URL(예: 'https://gjtennis.kr'), source.org_code 는 'gj' | 'jn'.
 */
export const gnuboardRankingParser: ParserFn = async (
  source: CrawlSource,
  ctx: ParserContext,
): Promise<CrawlResult> => {
  const org = source.org_code;
  if (!org) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: 'org_code 가 없다 — crawl_sources 설정 확인',
    };
  }

  // dispatcher 가 startAudit 에서 만든 클라이언트를 재사용한다(기존 파서 관례).
  // serviceClient() 를 새로 부르면 같은 키로 클라이언트만 하나 더 생긴다.
  const db = ctx.audit.supabase;
  const base = source.url.replace(/\/+$/, '');
  const failures: string[] = [];

  for (const [memberKind, suffix] of Object.entries(MEMBER_KIND_SUFFIX)) {
    const divisionCode = `${org}${suffix}`;
    const url = `${base}/sub4_5.php?member_kind=${encodeURIComponent(memberKind)}`;

    let html: string;
    try {
      const res = await fetch(url, { headers: COMMON_HEADERS });
      if (!res.ok) {
        failures.push(`${memberKind}: HTTP ${res.status}`);
        continue;
      }
      html = await res.text();
    } catch (e) {
      failures.push(`${memberKind}: ${e instanceof Error ? e.message : String(e)}`);
      continue;
    }

    const rows = parseRankingRows(html);

    // 0행 가드 — 반드시 교체 **앞**에 온다.
    //   협회가 레이아웃을 바꾸거나 HTTP 200 으로 에러 페이지를 주면(그누보드에서 흔하다)
    //   rows 가 빈다. 이때 교체를 실행하면 그 부서 랭킹이 통째로 지워지고 실패 기록도
    //   안 남아 'ok' 로 보고된다. 기존 데이터를 보존하고 시끄럽게 실패한다.
    if (rows.length === 0) {
      failures.push(`${memberKind}: 파싱 0행 — 기존 데이터 보존`);
      await saveRawDocument(ctx.audit, url, html, null, 'failed', '랭킹 행 0개');
      continue;
    }

    // audit 카운터는 dispatcher 의 finishAudit 이 crawl_audit 에 기록하는 값이다.
    // 직접 insert 하는 파서는 이걸 손으로 올려야 한다(upsertTournament 를 쓰지 않으므로).
    ctx.audit.fetched += rows.length;

    // 0점 선수 미저장 — 개인정보 최소화. 순위는 협회 값 그대로라 안 깨진다.
    const scored = rows.filter((r) => r.totalPoints > 0 || r.rankPoints > 0);

    // 원본 보관 — 기존 crawl_documents(raw zone) 인프라를 그대로 쓴다.
    await saveRawDocument(ctx.audit, url, html, null, 'parsed');

    // 교체는 RPC 한 번으로. PostgREST 로 delete → insert 를 나눠 쏘면 둘이 별도 커밋이라
    // delete 성공 + insert 실패 시 그 부서가 다음 크롤(최대 24h)까지 빈 채로 남는다.
    const { error: rpcErr } = await db.rpc('replace_org_ranking_division', {
      p_org: org,
      p_division: divisionCode,
      p_source_url: url,
      p_rows: scored.map((r) => ({
        rank: r.rank,
        player_name: r.playerName,
        org_player_id: r.orgPlayerId,
        club_raw: r.clubRaw,
        rank_points: r.rankPoints,
        total_points: r.totalPoints,
      })),
    });
    if (rpcErr) {
      failures.push(`${memberKind}: replace ${rpcErr.message}`);
      continue;
    }

    ctx.audit.inserted += scored.length;
  }

  return {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: 0,
    // 기존 파서 관례를 따른다(gnuboard_sub5_5_contest.ts 의 allFailed 판정).
    // 부분 실패는 error 메시지로 드러나고, dispatcher 가 crawl_audit 을 'partial' 로 내린다.
    status: failures.length === Object.keys(MEMBER_KIND_SUFFIX).length ? 'error' : 'ok',
    error: failures.length > 0 ? failures.join(' | ') : undefined,
  };
};
