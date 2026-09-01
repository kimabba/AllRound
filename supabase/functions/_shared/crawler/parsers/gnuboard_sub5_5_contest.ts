// _shared/crawler/parsers/gnuboard_sub5_5_contest.ts
//
// 광주/전남 협회 "대회일정" (sub5_2_2.php → sub5_2_2_view.php) 통합 parser.
//
// 배경:
//   광주/전남 모두 동일한 커스텀 대회일정 템플릿을 사용한다.
//   - Listing: /sub5_2_2.php  (대회목록, 제목 링크 → sub5_2_2_view.php?sid=NNN)
//   - Detail:  /sub5_2_2_view.php?sid=NNN  (부서별 접수기간·대회일 테이블)
//   이전에 크롤하던 sub5_5.php 는 공지게시판(이미지 공지)이라 날짜 추출 불가.
//   region 은 crawl_sources.region 으로 구분.
//
// 변경 감지:
//   해당 사이트는 ETag/Last-Modified 응답 헤더를 내보내지 않는다.
//   대신 listing 의 (sid|title) 목록을 정렬·해시한 값을 last_etag 컬럼에
//   `W/"sha256:..."` 형태로 저장해 동일 listing 일 때 304-동급으로 처리한다.
//
// 보안 / 안정성:
//   - User-Agent 명시 (운영자 식별 가능)
//   - listing 30건 cap
//   - upsert 시 status='draft' 로 들어가 어드민 승인 게이트 통과 필수

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractVenue,
  markListingSeen,
  saveRawDocument,
  upsertTournament,
} from '../../crawler.ts';
import { type DivisionDictRow, loadDivisionDict, mapDivisionsByDict } from '../divisions.ts';
import { extractPosterUrl } from '../poster.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';

const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};

interface BoardItem {
  url: string;
  title: string;
  sid: string;
}

/**
 * 신청현황표 셀의 **구분자 없는 8자리 날짜**를 훑는다 — 등장 순서대로 전부.
 *   '20260602 ~ 20260610 [마감]'  → ['2026-06-02', '2026-06-10']
 *   '20260614 09:00:00시'          → ['2026-06-14']
 *
 * 공용 extractDate 를 고치지 않는 이유: 그건 본문 전체를 훑으므로 계좌번호·전화번호의
 * 8자리 숫자를 날짜로 오인할 여지가 생긴다. 표 셀은 컬럼으로 문맥이 확정되므로
 * 여기서만 푼다. 연도는 공용 함수와 같은 범위(작년~+5년)로 제한한다.
 */
function extractCompactDates(text: string): string[] {
  const nowYear = new Date().getUTCFullYear();
  const out: string[] = [];
  for (const m of text.matchAll(/(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)/g)) {
    const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
    if (y < nowYear - 1 || y > nowYear + 5) continue;
    if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
    // 달력에 실재하는 날짜만 — 20260231 같은 값이 통과하면 안 된다(codex).
    const probe = new Date(Date.UTC(y, mo - 1, d));
    if (
      probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d
    ) {
      continue;
    }
    out.push(`${m[1]}-${m[2]}-${m[3]}`);
  }
  return out;
}

interface ListingResult {
  status: 200 | 304;
  html: string | null;
  etag: string | null;
  lastModified: string | null;
}

// =============================================================================
// listing 조건부 GET
// =============================================================================
async function fetchListing(
  listUrl: string,
  ctx: ParserContext,
): Promise<ListingResult> {
  const headers: Record<string, string> = { ...COMMON_HEADERS };
  if (ctx.previousEtag) headers['If-None-Match'] = ctx.previousEtag;
  if (ctx.previousLastModified) headers['If-Modified-Since'] = ctx.previousLastModified;

  const res = await fetch(listUrl, { headers });
  const etag = res.headers.get('etag');
  const lastModified = res.headers.get('last-modified');

  if (res.status === 304) {
    return { status: 304, html: null, etag, lastModified };
  }
  if (!res.ok) {
    throw new Error(`listing fetch failed ${res.status} for ${listUrl}`);
  }
  return { status: 200, html: await res.text(), etag, lastModified };
}

// =============================================================================
// listing 파싱 — sub5_2_2.php
// 링크: sub5_2_2_view.php?sid=NNN&...
// 제목: 링크 텍스트
// =============================================================================
export function parseListing(html: string, baseUrl: string): BoardItem[] {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('failed to parse listing HTML');

  const items: BoardItem[] = [];
  const seen = new Set<string>();

  // 두 계열을 모두 받는다.
  //   (a) 시협회·전남 커스텀 템플릿 : sub5_2_2_view.php?sid=NNN
  //   (b) 구 협회 표준 그누보드      : bbs/board.php?bo_table=game&wr_id=NNN
  // 목록 URL 에 bo_table 이 있으면 (b)로 보고 **같은 게시판** 링크만 모은다.
  // 게시판을 안 가리면 사이드바의 자유게시판·갤러리 글까지 대회로 긁힌다.
  let boTable: string | null = null;
  try {
    boTable = new URL(baseUrl).searchParams.get('bo_table');
  } catch {
    boTable = null;
  }

  const allLinks = dom.querySelectorAll('a[href]');
  for (const link of allLinks) {
    const el = link as unknown as {
      getAttribute(name: string): string | null;
      textContent: string;
    };
    const href = el.getAttribute('href') ?? '';

    let absolute: string;
    try {
      absolute = new URL(href, baseUrl).toString();
    } catch {
      continue;
    }

    let sid: string | null = null;
    if (boTable) {
      // 문자열 포함으로 보면 bo_table=game2 가 game 으로 통과한다(codex).
      // 파라미터로 파싱해 정확히 같은 값만 받는다.
      let linkTable: string | null = null;
      let wrId: string | null = null;
      try {
        const u = new URL(absolute);
        linkTable = u.searchParams.get('bo_table');
        wrId = u.searchParams.get('wr_id');
      } catch {
        continue;
      }
      if (linkTable !== boTable) continue;
      if (!wrId || !/^\d+$/.test(wrId)) continue;
      sid = wrId;
    } else {
      if (!href.includes('sub5_2_2_view') || !href.includes('sid=')) continue;
      const m = absolute.match(/[?&]sid=(\d+)/);
      if (!m) continue;
      sid = m[1];
    }

    const title = (el.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;
    if (seen.has(sid)) continue;
    seen.add(sid);

    items.push({ url: absolute, title, sid });
  }
  return items;
}

// =============================================================================
// listing 컨텐츠 해시 (서버 ETag 없을 때 변경 감지용)
// =============================================================================
async function listingContentHash(items: BoardItem[]): Promise<string> {
  const stable = items
    .map((it) => `${it.sid}|${it.title}`)
    .sort()
    .join('\n');
  const data = new TextEncoder().encode(stable);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `W/"sha256:${hex}"`;
}

// =============================================================================
// 상세 페이지 fetch + 정규화 — sub5_2_2_view.php
//
// 페이지 구조:
//   - 제목: <h3> 또는 listing 링크 텍스트(titleHint로 전달)
//   - 날짜: 테이블 td 내 "YYYY년 MM월 DD일" 텍스트
//     · 접수기간: "2026년 4월 27일 ~ 2026년 5월 05일 18시 까지"
//     · 대회일:   "2026년 5월 09일"
// =============================================================================
export async function fetchDetail(
  detailUrl: string,
  region: string,
  titleHint: string,
  dict: DivisionDictRow[],
): Promise<
  {
    rawHtml: string;
    canonicalContent: string;
    tournament: CrawlerTournament | null;
  } | null
> {
  const res = await fetch(detailUrl, { headers: COMMON_HEADERS });
  if (!res.ok) return null; // fetch 실패 — 보관할 원본 자체가 없음
  const html = await res.text();
  // 이 지점부터는 원본(html)을 확보했으므로, 파싱 가드 실패 시에도
  // { rawHtml, tournament: null } 로 반환해 dispatch 가 raw 를 failed 로 보관한다.
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return { rawHtml: html, canonicalContent: '', tournament: null };

  // 제목: h3 우선, 없으면 listing 링크 텍스트(titleHint) 사용.
  //
  // 표준 그누보드 상세(#bo_v_con)는 h3 가 **게시판 이름**인 경우가 있다 — 지도자회는
  // h3='대회관련' 이라 모든 대회 제목이 같아진다. 그 페이지에서만 <title> 의 ' > ' 앞을
  // 쓴다. **커스텀 템플릿(광주·전남)에는 적용하지 않는다** — 거기 <title> 은
  // '광주광역시테니스협회 …' 같은 사이트명이라, 길이만 비교하면 실제 대회 제목을
  // 협회명으로 덮어쓴다(실물 회귀로 확인).
  const h3El = dom.querySelector('h3');
  let title = (h3El?.textContent ?? '').replace(/\s+/g, ' ').trim() || titleHint;
  if (dom.querySelector('#bo_v_con')) {
    // 표준 그누보드의 <title> 은 '{글 제목} > {게시판} | {사이트명}' 이다.
    // 길이 비교로 고르면 h3 가 진짜 제목인 사이트에서도 덮어쓸 수 있다(codex).
    // h3 가 그 글 제목에 **들어 있지 않을 때만** 게시판 이름으로 보고 갈아탄다.
    //   지도자회 h3='대회관련'  → 제목에 없음 → <title> 사용
    //   북구     h3='제26회 …' → 제목에 있음 → h3 유지
    const docTitle = (dom.querySelector('title')?.textContent ?? '')
      .split('>')[0].replace(/\s+/g, ' ').trim();
    if (docTitle && title && !docTitle.includes(title)) title = docTitle;
    else if (docTitle && !title) title = docTitle;
  }
  if (!title) return { rawHtml: html, canonicalContent: '', tournament: null };

  // 노이즈 태그 제거 후 대회 콘텐츠 영역의 텍스트만 추출한다. 광주 협회
  // 페이지의 푸터는 <footer>가 아니라 <div class="footer">라서, body 전체를
  // 읽으면 협회 사무실 주소의 "진월국제테니스장"을 대회 장소로 오인한다.
  const bodyEl = dom.querySelector('body');
  if (bodyEl) {
    const noiseNodes = bodyEl.querySelectorAll(
      'script, style, nav, header, footer, aside, .footer, .gnb, .lnb, .snb',
    );
    for (const node of noiseNodes) {
      node.parentNode?.removeChild(node);
    }
  }
  // #bo_v_con 은 표준 그누보드의 **본문** 컨테이너다. 이게 없으면 body 로 떨어져
  // 사이드바(최신글·인기검색어·캘린더)까지 본문으로 읽혀 장소·참가비가 엉킨다.
  const contentRoot = dom.querySelector('.docContWrap') ??
    dom.querySelector('#bo_v_con') ??
    dom.querySelector('#bo_v') ??
    dom.querySelector('main') ??
    dom.querySelector('body');
  const bodyText = (contentRoot?.textContent ?? '').replace(/\s+/g, ' ').trim();

  // 본문 컨테이너 안의 첫 유효 이미지를 포스터로 수집한다(P6). 노이즈 요소는 위에서
  // 이미 제거됐으므로 로고·배너가 아닌 협회 업로드 포스터가 잡힌다. 없으면 undefined
  // 로 남겨 upsert 가 기존 poster_url 을 보존한다(KTA 와 동일 규칙).
  const posterUrl = extractPosterUrl(contentRoot?.innerHTML ?? null, detailUrl);

  // ── 테이블 기반 추출 (참가부서 / 신청기간 / 경기일시) ──
  // 테이블 헤더: 참가부서 | 구분 | 신청기간 | 경기일시 | ...
  //
  // 세 컬럼을 **같은 표 안에서** 함께 읽는다. 예전에는 컬럼 인덱스를 문서 전체 th
  // 순번으로 잡고 값도 문서 전체 tr 에서 읽었다 — 상세 페이지에 표가 하나뿐인
  // 시협회에서는 우연히 맞았지만, 구 협회 페이지처럼 요강표가 함께 있으면 인덱스가
  // 어긋나 엉뚱한 칸을 날짜로 읽는다. 실제로 광산구·서구 2025년 대회에서 **마감일이
  // 경기일보다 늦게** 나왔다(2025-11-05 경기인데 마감 2025-12-05).
  let tableStartDate: string | null = null;
  let tableDeadline: string | null = null;
  // 부서별로 경기일이 다른 대회가 있다(빛고을배: 일반부 8/30, 지동부 7/05).
  // 마감일 clamp 는 **가장 늦은 경기일**과 비교해야 정상 대회를 잘못 비우지 않는다.
  let tableLastStartDate: string | null = null;

  // 개설 부서는 `참가부서` 컬럼에만 있다. 본문에는 개설되지 않은 부서명이
  // 자격 조건 설명으로 등장한다 — 실제 광주 대회(sid=108) 원문 기준:
  //   "…자격을 취득할 경우 골드부 5.0 등급으로 승급되며"  (승급 규칙)
  //   "구분 청년부 장년부 베테랑부 순수동호인 20세이상"    (연령 구분표)
  // 본문 전체를 사전에 넣으면 이런 설명문까지 개설 부서로 잡혀, 나갈 수 없는
  // 대회가 "내 등급 대회"로 뜬다. 컬럼이 없는 사이트는 기존 본문 매칭으로 폴백.
  //
  // 수집 범위는 반드시 `참가부서` 헤더를 가진 그 표 하나로 한정한다. 상세 페이지는
  // 요강 본문도 표로 짜여 있어(광주 sid=108 은 표 여러 개·tr 179 개), 문서 전체의
  // tr 을 훑으면 요강 표의 첫 칸까지 들어와 본문 매칭과 다를 바 없어진다.
  const isDivisionHeader = (t: string) =>
    t.includes('참가부서') || t === '부서' || t.includes('경기종목');

  const divisionCells: string[] = [];
  {
    // **문서 전체**를 훑는다. contentRoot 로 좁히면 안 된다 — 구 협회 사이트의
    // 신청현황표는 본문 컨테이너(#bo_v_con) **밖(앞)** 에 렌더된다(실측: coach 는
    // 표 위치 27110 < bo_v_con 35060, 북구는 37131 < 38222). 좁혔더니 구별 4곳이
    // 전부 파싱 실패로 돌아섰다. 무관한 표에 대한 방어는 범위가 아니라 (1) 위쪽에서
    // 노이즈 요소(nav/header/footer/aside/.footer/.gnb/.lnb/.snb)를 DOM 에서 제거하고
    // (2) 부서 컬럼이 있는 표만 1차로 보는 것으로 한다.
    const tables = dom.querySelectorAll('table');
    for (const tableNode of tables) {
      const table = tableNode as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
      const rows = table.querySelectorAll('tr');
      if (rows.length === 0) continue;

      // 헤더는 표의 **첫 행**에만 있는 것으로 본다. 신청현황표는 헤더가 맨 위다.
      // 본문 아무 행에서나 라벨을 찾으면 요강 본문표까지 걸린다 — 광주 sid=108 의
      // 요강표(tr 176개)는 25번째 행에서 라벨이 매치돼, 컬럼 정렬이 맞지 않는
      // 본문 셀(장소 등)까지 부서로 긁혔다.
      //
      // 태그는 가리지 않는다. 같은 사이트 계열이라도 헤더를 <th> 로 쓰는 페이지와
      // <td> 로 쓰는 페이지가 섞여 있다(tests 의 실원본 모사 BODY_FIXTURE 참고).
      const head = rows[0] as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
      const headCells = head.querySelectorAll('th, td');
      let divIdx = -1;
      let dateIdx = -1;
      let deadlineIdx = -1;
      for (let c = 0; c < headCells.length; c++) {
        const t = ((headCells[c] as unknown as { textContent: string }).textContent ?? '')
          .replace(/\s+/g, '').trim();
        if (divIdx < 0 && isDivisionHeader(t)) divIdx = c;
        if (dateIdx < 0 && (t.includes('경기일시') || t.includes('대회일'))) dateIdx = c;
        if (deadlineIdx < 0 && (t.includes('신청기간') || t.includes('접수기간'))) deadlineIdx = c;
      }
      // 부서 컬럼이 없는 표는 신청현황표가 아니다 — 날짜도 읽지 않는다.
      if (divIdx < 0) continue;

      // 헤더 다음 행부터가 데이터다. 부서·날짜를 같은 행에서 함께 읽는다.
      for (let r = 1; r < rows.length; r++) {
        const row = rows[r] as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
        const cells = row.querySelectorAll('th, td');
        const cellText = (i: number) =>
          ((cells[i] as unknown as { textContent: string }).textContent ?? '')
            .replace(/\s+/g, ' ').trim();

        if (cells.length > divIdx) {
          const cell = cellText(divIdx);
          if (cell) divisionCells.push(cell);
        }

        // 경기일: 첫 데이터 행의 값을 대회일로 쓰고, 최댓값은 clamp 용으로 따로 둔다.
        if (dateIdx >= 0 && cells.length > dateIdx) {
          const t = cellText(dateIdx);
          // 구별 협회는 '20260614 09:00:00시' 처럼 구분자 없이 쓴다.
          const d = extractDate(t) ?? extractCompactDates(t)[0] ?? null;
          if (d) {
            if (!tableStartDate) tableStartDate = d;
            if (!tableLastStartDate || d > tableLastStartDate) tableLastStartDate = d;
          }
        }

        // 신청기간: "2026년 6월 22일 ~ 2026년 7월 01일 18시 까지" → 마지막 날짜가 마감일
        // 구별 협회는 "20260602 ~ 20260610 [마감]" → 역시 마지막이 마감일
        if (deadlineIdx >= 0 && !tableDeadline && cells.length > deadlineIdx) {
          const t = cellText(deadlineIdx);
          const allDates: string[] = [];
          const dateRegex = /(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/g;
          let dm;
          while ((dm = dateRegex.exec(t)) !== null) {
            const yi = Number(dm[1]), mi = Number(dm[2]), di = Number(dm[3]);
            if (yi >= 2024 && yi <= 2030 && mi >= 1 && mi <= 12 && di >= 1 && di <= 31) {
              allDates.push(
                `${dm[1]}-${String(mi).padStart(2, '0')}-${String(di).padStart(2, '0')}`,
              );
            }
          }
          if (allDates.length === 0) allDates.push(...extractCompactDates(t));
          if (allDates.length > 0) tableDeadline = allDates[allDates.length - 1];
        }
      }
    }
  }

  // 부서 컬럼이 있는 표에 날짜 컬럼이 없는 사이트도 있을 수 있다. 예전 코드는 문서
  // 전역에서 날짜를 읽어 그 경우가 우연히 커버됐다 — 표 단위로 좁히면서 잃은 경로라
  // 2차 시도로 되살린다(부서는 이미 확정됐으므로 날짜만 본다).
  if (!tableStartDate || !tableDeadline) {
    // **문서 전체**를 훑는다. contentRoot 로 좁히면 안 된다 — 구 협회 사이트의
    // 신청현황표는 본문 컨테이너(#bo_v_con) **밖(앞)** 에 렌더된다(실측: coach 는
    // 표 위치 27110 < bo_v_con 35060, 북구는 37131 < 38222). 좁혔더니 구별 4곳이
    // 전부 파싱 실패로 돌아섰다. 무관한 표에 대한 방어는 범위가 아니라 (1) 위쪽에서
    // 노이즈 요소(nav/header/footer/aside/.footer/.gnb/.lnb/.snb)를 DOM 에서 제거하고
    // (2) 부서 컬럼이 있는 표만 1차로 보는 것으로 한다.
    const tables = dom.querySelectorAll('table');
    for (const tableNode of tables) {
      const table = tableNode as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
      const rows = table.querySelectorAll('tr');
      if (rows.length === 0) continue;
      const head = rows[0] as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
      const headCells = head.querySelectorAll('th, td');
      let dateIdx = -1;
      let deadlineIdx = -1;
      for (let c = 0; c < headCells.length; c++) {
        const t = ((headCells[c] as unknown as { textContent: string }).textContent ?? '')
          .replace(/\s+/g, '').trim();
        if (dateIdx < 0 && (t.includes('경기일시') || t.includes('대회일'))) dateIdx = c;
        if (deadlineIdx < 0 && (t.includes('신청기간') || t.includes('접수기간'))) deadlineIdx = c;
      }
      if (dateIdx < 0 && deadlineIdx < 0) continue;
      for (let r = 1; r < rows.length; r++) {
        const row = rows[r] as unknown as { querySelectorAll(s: string): ArrayLike<unknown> };
        const cells = row.querySelectorAll('th, td');
        const cellText = (i: number) =>
          ((cells[i] as unknown as { textContent: string }).textContent ?? '')
            .replace(/\s+/g, ' ').trim();
        // 첫 값만 대회일로 쓰되, **모든 행**을 훑어 최댓값(clamp 기준)을 갱신한다.
        // !tableStartDate 로 조건을 걸면 둘째 행부터 건너뛰어 clamp 가 첫 행 기준으로
        // 되돌아간다(codex).
        if (dateIdx >= 0 && cells.length > dateIdx) {
          const t = cellText(dateIdx);
          const d = extractDate(t) ?? extractCompactDates(t)[0] ?? null;
          if (d) {
            if (!tableStartDate) tableStartDate = d;
            if (!tableLastStartDate || d > tableLastStartDate) tableLastStartDate = d;
          }
        }
        if (deadlineIdx >= 0 && !tableDeadline && cells.length > deadlineIdx) {
          const t = cellText(deadlineIdx);
          const dates = extractCompactDates(t);
          const korean: string[] = [];
          for (const dm of t.matchAll(/(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/g)) {
            korean.push(
              `${dm[1]}-${String(Number(dm[2])).padStart(2, '0')}-${
                String(Number(dm[3])).padStart(2, '0')
              }`,
            );
          }
          const all = korean.length > 0 ? korean : dates;
          if (all.length > 0) tableDeadline = all[all.length - 1];
        }
      }
      if (tableStartDate && tableDeadline) break;
    }
  }

  // 테이블 파싱 실패 시 기존 fallback
  const startDate = tableStartDate ?? extractDate(bodyText) ?? extractDate(title);
  if (!startDate) return { rawHtml: html, canonicalContent: bodyText, tournament: null };

  const { codes: gradeCodes, label: divisionLabel } = mapDivisionsByDict(
    divisionCells.length > 0 ? divisionCells.join(' ') : `${title} ${bodyText}`,
    dict,
  );
  const hasExplicitUnknownDivision = /부서\s*(?:추후\s*공지|미정|확인\s*필요)/.test(bodyText);

  // 마감일이 경기일보다 늦으면 버린다. 파싱 오류가 아니라 **원본이 그렇다** —
  // 구 협회 사이트는 마감된 대회의 신청기간 끝을 나중 날짜로 늘려 적어둔다:
  //   광산구 2025: 신청기간 20251018~20251205 / 경기일 20251105
  //   서구   2025: 신청기간 20251027~20260129 / 경기일 20251101
  // 그대로 두면 앱이 이미 끝난 대회를 "마감 D-30" 으로 보여준다. 값을 지어내지 않고
  // 비운다 — 마감 미상이면 알림도 안 가고 카드에 D-day 도 안 뜬다.
  const rawDeadline = tableDeadline ?? extractApplicationDeadline(bodyText) ?? undefined;
  const clampAgainst = tableLastStartDate && tableLastStartDate > startDate
    ? tableLastStartDate
    : startDate;
  const deadline = rawDeadline && rawDeadline > clampAgainst ? undefined : rawDeadline;

  // ── 참가비 추출 ──
  // "참가비팀당 34,000원" / "참가비 팀당 30,000원" / "참가비인당 15,000원"
  let entryFee: number | undefined;
  const feeMatch = bodyText.match(/참가비\s*(?:[:：]\s*)?(?:(팀당|인당)\s*)?([0-9,]+)\s*원/);
  if (feeMatch) {
    const amount = Number(feeMatch[2].replace(/,/g, ''));
    if (amount > 0 && amount < 1_000_000) {
      entryFee = amount;
    }
  }

  // ── 주최/주관 추출 ──
  // "주 최영암군 체육회" / "주최 : 광주테니스협회" — 공백이 섞여 있음
  let organizer: string | undefined;
  const orgMatch = bodyText.match(
    /주\s*최\s*[:：]?\s*([가-힣A-Za-z0-9()（）\s]{2,30}?)(?:주\s*관|후\s*원|협\s*찬|참가비|$)/,
  );
  if (orgMatch) {
    organizer = orgMatch[1].replace(/\s+/g, ' ').trim();
  }
  if (!organizer) {
    organizer = region ? `${region}테니스협회` : undefined;
  }

  const location = extractVenue(bodyText) ?? undefined;
  const tournament: CrawlerTournament = {
    title,
    start_date: startDate,
    application_deadline: deadline,
    region,
    location,
    eligible_grades: gradeCodes,
    division_label_local: hasExplicitUnknownDivision ? '부서추후공지' : divisionLabel,
    clear_eligible_grades: hasExplicitUnknownDivision || undefined,
    poster_url: posterUrl ?? undefined,
    source_url: detailUrl,
    organizer,
    entry_fee: entryFee,
  };
  return {
    rawHtml: html,
    canonicalContent: JSON.stringify({
      title,
      bodyText,
      startDate,
      tableLastStartDate,
      tableDeadline,
      divisionCells,
    }),
    tournament,
  };
}

// =============================================================================
// parser entry point
// =============================================================================
export const gnuboardSub5_5ContestParser: ParserFn = async (
  source: CrawlSource,
  ctx: ParserContext,
): Promise<CrawlResult> => {
  const region = source.region ?? '';

  // 1) listing fetch (conditional GET)
  let listing: ListingResult;
  try {
    listing = await fetchListing(source.url, ctx);
  } catch (e) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: (e as Error).message,
    };
  }

  if (listing.status === 304) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'no_change',
      etag: listing.etag ?? ctx.previousEtag ?? null,
      last_modified: listing.lastModified ?? ctx.previousLastModified ?? null,
    };
  }

  // 2) parse listing
  let items: BoardItem[];
  try {
    items = parseListing(listing.html!, source.url);
  } catch (e) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: (e as Error).message,
    };
  }

  // 목록이탈 만료 판정 기준 — "목록에 있음"을 상세 파싱 성공이 아니라 여기서
  // 확정한다(CAP·상세 실패로 상세를 안 가는 항목도 목록엔 있다).
  await markListingSeen(ctx.audit, items.map((it) => it.url));

  if (items.length === 0) {
    const hash = await listingContentHash(items);
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'ok',
      etag: listing.etag ?? hash,
      last_modified: listing.lastModified ?? null,
    };
  }

  // 3) content-hash 변경 감지
  const computedHash = await listingContentHash(items);
  const effectiveEtag = listing.etag ?? computedHash;
  if (!listing.etag && ctx.previousEtag && ctx.previousEtag === computedHash) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'no_change',
      etag: computedHash,
      last_modified: ctx.previousLastModified ?? null,
    };
  }

  // 4) 상세 페이지 처리 — 협회는 crawl_sources.org_code 로 결정(추론 금지).
  const org = source.org_code;
  if (!org) {
    return {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: 'crawl_sources.org_code 미설정 — 파서가 org를 추론하지 않는다',
    };
  }
  // org 사전을 crawl당 1회 로드(detail마다 재조회 금지)
  const dict = await loadDivisionDict(ctx.audit.supabase, org);
  const errors: string[] = [];
  let parseFailures = 0;
  for (const item of items.slice(0, 30)) {
    try {
      const result = await fetchDetail(item.url, region, item.title, dict);
      if (!result) continue; // fetch 실패 — 보관할 원본 자체가 없음
      if (result.tournament) {
        // 파싱 성공: tournaments upsert + 원본을 parsed 로 보관·연결
        await upsertTournament(ctx.audit, 'tennis', result.tournament, {
          rawHtml: result.rawHtml,
          canonicalContent: result.canonicalContent,
        });
      } else {
        // 파싱 가드 미통과: 원본을 failed 로 보관해 파서 수정 후 재처리 가능하게 한다.
        // (raw zone 이 존재하는 핵심 목적 — 파서가 깨진 케이스를 놓치지 않는다.)
        await saveRawDocument(
          ctx.audit,
          item.url,
          result.rawHtml,
          null,
          'failed',
          '파싱 실패: 가드 미통과(DOM/제목/날짜)',
        );
        ctx.audit.fetched++;
        parseFailures++;
      }
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  // 상세를 가져왔는데 단 한 건도 파싱 성공하지 못하면 사이트 구조 변경을 의심한다.
  // status='error' 로 반환해 dispatcher 가 last_status=error + last_error 로 기록 →
  // 수동 실행 UI/운영에서 "성공"으로 오인되지 않게 한다.
  // (개별 게시글의 파싱 실패는 정상일 수 있으므로 "전부 실패"일 때만 error 처리)
  const allFailed = parseFailures > 0 && ctx.audit.inserted + ctx.audit.updated === 0;
  if (allFailed) {
    errors.push(`상세 ${parseFailures}건 모두 파싱 실패 — 사이트 구조 변경 의심`);
  }

  // 전건 실패 시에는 변경감지 캐시(etag/last_modified)를 null 로 비운다.
  // dispatcher 는 result.etag !== undefined 일 때만 last_etag 를 갱신하므로
  // undefined 를 주면 이전 성공 크롤의 stale etag 가 남아, 다음 스케줄 실행이
  // 같은 listing 해시에서 no-change 로 일찍 종료해 자동 재시도가 막힌다.
  // null 로 비우면 다음 실행의 previousEtag 가 falsy → no-change 우회 → 재시도.
  // (성공/부분성공 시에만 변경감지 캐시를 갱신한다.)
  return {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: ctx.audit.updated,
    status: allFailed ? 'error' : 'ok',
    error: errors.length > 0 ? errors.slice(0, 5).join('\n') : undefined,
    etag: allFailed ? null : effectiveEtag,
    last_modified: allFailed ? null : (listing.lastModified ?? null),
  };
};
