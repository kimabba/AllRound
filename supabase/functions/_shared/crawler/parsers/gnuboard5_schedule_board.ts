// _shared/crawler/parsers/gnuboard5_schedule_board.ts
//
// 표준 그누보드5 "대회일정" 게시판 parser. 첫 대상: 전북(jbsta.com).
//   - Listing: /bbs/board.php?bo_table=schedule&gubun=list  (리스트 뷰. 기본은 캘린더 뷰)
//   - Detail:  /bbs/board.php?bo_table=schedule&wr_id=N
//
// 실측 구조(2026-08 확인, tests/fixtures/jb_schedule_*.html):
//   - charset UTF-8 (EUC-KR 아님 — TextDecoder 분기 불필요)
//   - 상세의 신청현황표 = <table class="take_part">, 헤더가 "참 가 부 서 | 신 청 기 간 |
//     경 기 일 시 | …" 처럼 글자 사이 공백이 섞여 있어 매칭 전 공백을 전부 제거한다.
//   - 날짜는 연도가 없다: "04월03일 ~ 04월19일[신청마감]" / "04월25일09시분"
//     → extractMonthDays + inferYear 로 연도를 부여한다(아래 규약).
//   - 본문(#bo_v_con)은 포스터 이미지뿐이라 참가비·장소·주최 텍스트 추출은 기대하지
//     않는다(장소는 extractVenue 기회적 시도만). 포스터 URL 은 poster_url 로 수집.
//
// 연도 추론 규약(docs/team/PLAN-local-nightly-crawl.md Phase 2):
//   1. 앵커연도 = 제목/본문의 4자리 연도 → 없으면 그누보드 작성일(#bo_v_info) →
//      없으면 크롤시점 KST 연도.
//   2. 시간축(신청시작→마감→경기일) 단조증가 보정: 다음 날짜가 이전보다 앞서면
//      +1년(연말·연초 걸침).
//   3. 크롤시점 보정(앵커가 3번 폴백일 때만): 경기일이 전부 60일+ 과거면 +1년.
//   4. sanity: 경기일이 크롤시점 기준 −12~+18개월 밖이면 추론실패 → tournament null.
//   now 를 파라미터로 받아 테스트 결정성을 확보한다.
//
// 안전 규약(기존 파서 공통):
//   - canonical source_url 재구성(bo_table+wr_id 만 유지) — 페이지네이션 파라미터가
//     붙은 URL 로 중복 insert 되는 것을 막는다.
//   - wr_id 기준 dedupe(공지 상단고정 이중출현), 빈 텍스트(이미지) 앵커 skip.
//   - 상세 fetch 30건 cap, 전건 파싱실패 → status='error' + etag null(재시도 유도).
//   - upsert 는 status='draft' — 어드민 승인 게이트 통과 필수.
//   - org 는 crawl_sources.org_code 로 결정, 추론 금지. 부서는 mapDivisionsByDict.

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractVenue,
  markListingSeen,
  saveRawDocument,
  upsertTournament,
} from '../../crawler.ts';
import { type DivisionDictRow, loadDivisionDict, mapDivisionsByDict } from '../divisions.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};
const DETAIL_CAP = 30;
// 파서 결과 의미가 바뀌면 올린다 — 목록이 그대로여도 상세를 다시 읽게 한다.
const PARSER_REVISION = '2026-08-p6-initial';

// deno-dom 요소를 최소 인터페이스로 좁혀 쓰기 위한 캐스트 헬퍼(kato_openlist 와 동일).
type El = {
  getAttribute(name: string): string | null;
  textContent: string;
  querySelector(sel: string): El | null;
  querySelectorAll(sel: string): ArrayLike<El> & Iterable<El>;
};

export interface ScheduleBoardItem {
  wrId: string;
  url: string; // canonical: board.php?bo_table=X&wr_id=N
  title: string;
}

// =============================================================================
// 목록 파싱 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export function parseScheduleListing(html: string, baseUrl: string): ScheduleBoardItem[] {
  const boTable = new URL(baseUrl).searchParams.get('bo_table');
  if (!boTable) throw new Error('listing url 에 bo_table 파라미터가 필요하다');

  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('failed to parse listing HTML');

  const items: ScheduleBoardItem[] = [];
  const seen = new Set<string>();
  for (const link of (dom as unknown as El).querySelectorAll('a[href]')) {
    const href = link.getAttribute('href') ?? '';
    let u: URL;
    try {
      u = new URL(href, baseUrl);
    } catch {
      continue;
    }
    // 같은 게시판의 글 링크만 — 사이드바의 다른 게시판(ranking 등) 글을 배제한다.
    if (u.searchParams.get('bo_table') !== boTable) continue;
    const wrId = u.searchParams.get('wr_id');
    if (!wrId || !/^\d+$/.test(wrId)) continue;

    // 빈 텍스트(이미지) 앵커 skip — 제목이 없으면 대회로 쓸 수 없다.
    const title = (link.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;

    // 공지 상단고정으로 같은 글이 목록에 두 번 나온다 — wr_id 기준 dedupe.
    if (seen.has(wrId)) continue;
    seen.add(wrId);

    // canonical URL 재구성: &page=&sfl=&stx= 등 페이지네이션·검색 파라미터를 버린다.
    // 같은 글이 파라미터만 다른 URL 로 들어와 중복 insert 되는 것을 막는다.
    items.push({
      wrId,
      url: `${u.origin}${u.pathname}?bo_table=${encodeURIComponent(boTable)}&wr_id=${wrId}`,
      title,
    });
  }
  return items;
}

// =============================================================================
// 연도 없는 날짜 추출 + 연도 추론 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export interface MonthDay {
  month: number;
  day: number;
}

/** "04월03일 ~ 04월19일[신청마감]" → [{month:4,day:3},{month:4,day:19}] (전수 매치). */
export function extractMonthDays(text: string): MonthDay[] {
  const out: MonthDay[] = [];
  for (const m of text.matchAll(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/g)) {
    const month = Number(m[1]);
    const day = Number(m[2]);
    if (month < 1 || month > 12 || day < 1 || day > 31) continue;
    out.push({ month, day });
  }
  return out;
}

export type AnchorSource = 'text' | 'written' | 'crawl';
export interface YearAnchor {
  year: number;
  source: AnchorSource;
}

function kstYear(now: Date): number {
  return new Date(now.getTime() + 9 * 3600_000).getUTCFullYear();
}

/**
 * 앵커연도 결정: 제목/본문 4자리 연도 → 그누보드 작성일(#bo_v_info, 'YY-MM-DD') →
 * 크롤시점 KST 연도. 본문은 연도 아닌 숫자(조회수 등)가 많아 '년' 접미를 요구한다.
 */
export function resolveAnchorYear(
  title: string,
  bodyText: string,
  infoText: string,
  now: Date,
): YearAnchor {
  const t = title.match(/(?<!\d)(20[2-4]\d)(?!\d)/);
  if (t) return { year: Number(t[1]), source: 'text' };
  const b = bodyText.match(/(?<!\d)(20[2-4]\d)\s*년/);
  if (b) return { year: Number(b[1]), source: 'text' };
  const w4 = infoText.match(/(?<!\d)(20[2-4]\d)-\d{2}-\d{2}/);
  if (w4) return { year: Number(w4[1]), source: 'written' };
  const w2 = infoText.match(/(?<!\d)(\d{2})-\d{2}-\d{2}(?!\d)/);
  if (w2) return { year: 2000 + Number(w2[1]), source: 'written' };
  return { year: kstYear(now), source: 'crawl' };
}

function shiftMonthsIso(now: Date, months: number): string {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + months, now.getUTCDate()))
    .toISOString().slice(0, 10);
}

const pad2 = (n: number) => String(n).padStart(2, '0');

/**
 * 시간축 순서(신청시작→마감→경기일…)의 MonthDay 열에 연도를 부여한다.
 *   - timeline[gameStartIndex..] 가 경기일 — 크롤시점 보정·sanity 는 경기일에만 건다.
 *   - 반환은 입력과 같은 길이의 'YYYY-MM-DD' 배열. 추론실패(sanity 밖·달력에 없는
 *     날짜)는 null — 호출부가 그 행/대회를 버린다(값을 지어내지 않는다).
 */
export function inferYear(
  timeline: MonthDay[],
  gameStartIndex: number,
  anchor: YearAnchor,
  now: Date,
): string[] | null {
  if (timeline.length === 0) return [];
  let year = anchor.year;
  let prev: MonthDay | null = null;
  let dates: string[] = [];
  for (const md of timeline) {
    // 단조증가 보정: 다음 날짜가 이전보다 앞서면 해를 넘긴 것(12월 접수 → 1월 경기).
    if (
      prev !== null && (md.month < prev.month || (md.month === prev.month && md.day < prev.day))
    ) {
      year += 1;
    }
    // 달력에 실재하는 날짜만(2월 30일 등은 표 오독 의심 → 전체 실패).
    const probe = new Date(Date.UTC(year, md.month - 1, md.day));
    if (
      probe.getUTCFullYear() !== year || probe.getUTCMonth() !== md.month - 1 ||
      probe.getUTCDate() !== md.day
    ) {
      return null;
    }
    dates.push(`${year}-${pad2(md.month)}-${pad2(md.day)}`);
    prev = md;
  }

  // 크롤시점 보정 — 앵커가 크롤연도 폴백일 때만. 경기일이 전부 60일+ 과거면
  // 내년 대회를 올해로 오인한 것으로 보고 전체를 +1년.
  if (anchor.source === 'crawl') {
    const cutoff = new Date(now.getTime() - 60 * 86_400_000).toISOString().slice(0, 10);
    const games = dates.slice(gameStartIndex);
    if (games.length > 0 && games.every((d) => d < cutoff)) {
      dates = dates.map((d) => `${Number(d.slice(0, 4)) + 1}${d.slice(4)}`);
    }
  }

  // sanity: 경기일이 −12~+18개월 밖이면 추론실패.
  const lo = shiftMonthsIso(now, -12);
  const hi = shiftMonthsIso(now, 18);
  for (const d of dates.slice(gameStartIndex)) {
    if (d < lo || d > hi) return null;
  }
  return dates;
}

// =============================================================================
// 상세 파싱 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export interface ScheduleDetail {
  title: string;
  startDate: string;
  endDate: string | null;
  deadline: string | null;
  divisionText: string; // 참가부서 셀 원문 join (부서 컬럼이 없으면 '')
  posterUrl: string | null;
  bodyText: string; // 기회적 추출(extractVenue)용
}

const normalize = (s: string) => s.replace(/\s+/g, '');
const isGameHeader = (t: string) => t.includes('경기일') || t.includes('대회일');
const isDeadlineHeader = (t: string) => t.includes('신청기간') || t.includes('접수기간');
const isDivisionHeader = (t: string) =>
  t.includes('참가부서') || t === '부서' || t.includes('부문');

export function parseScheduleDetail(
  html: string,
  titleHint: string,
  now: Date,
): ScheduleDetail | null {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;
  const root = dom as unknown as El;

  const title = (root.querySelector('#bo_v_title')?.textContent ?? '')
    .replace(/\s+/g, ' ').trim() || titleHint;
  if (!title) return null;

  // 본문(#bo_v_atc)은 신청현황표+포스터 이미지 영역. 앵커연도·장소 추출에만 쓴다.
  const bodyText = (root.querySelector('#bo_v_atc')?.textContent ?? '')
    .replace(/\s+/g, ' ').trim();
  const infoText = (root.querySelector('#bo_v_info')?.textContent ?? '').trim();
  const anchor = resolveAnchorYear(title, bodyText, infoText, now);

  // 표 스코프: 헤더(첫 행)에 경기일 + 신청기간 컬럼을 **모두** 가진 표만 신청현황표로
  // 본다. 문서 전체 th 를 훑으면 요강 본문표가 섞인다(gj 파서에서 실증된 함정).
  const gameDates: string[] = [];
  const deadlines: string[] = [];
  const divisionCells: string[] = [];
  for (const table of root.querySelectorAll('table')) {
    const rows = table.querySelectorAll('tr');
    if (rows.length === 0) continue;
    const headCells = rows[0].querySelectorAll('th, td');
    let gameIdx = -1;
    let deadlineIdx = -1;
    let divIdx = -1;
    for (let c = 0; c < headCells.length; c++) {
      const t = normalize(headCells[c].textContent ?? '');
      if (gameIdx < 0 && isGameHeader(t)) gameIdx = c;
      if (deadlineIdx < 0 && isDeadlineHeader(t)) deadlineIdx = c;
      if (divIdx < 0 && isDivisionHeader(t)) divIdx = c;
    }
    if (gameIdx < 0 || deadlineIdx < 0) continue;

    for (let r = 1; r < rows.length; r++) {
      const cells = rows[r].querySelectorAll('th, td');
      const cellText = (i: number) =>
        i >= 0 && i < cells.length ? (cells[i].textContent ?? '').replace(/\s+/g, ' ').trim() : '';

      const applyMds = extractMonthDays(cellText(deadlineIdx));
      const gameMds = extractMonthDays(cellText(gameIdx));
      if (gameMds.length === 0) continue; // 경기일 없는 행은 쓸 수 없다

      // 경기일 체인은 마감이 아니라 신청 '시작'에 잇는다. 마감이 경기일보다 늦게
      // 적힌 원본(gj 광산구/서구에서 실증)에서 단조증가 보정이 경기 연도를 +1
      // 오염시키는 것을 막는다 — 그런 마감은 아래 clamp 가 비운다.
      const gameTimeline = applyMds.length > 0 ? [applyMds[0], ...gameMds] : gameMds;
      const gameStart = applyMds.length > 0 ? 1 : 0;
      const gameDated = inferYear(gameTimeline, gameStart, anchor, now);
      if (gameDated === null) continue; // 이 행만 버린다 — 다른 부서 행은 살릴 수 있다.
      gameDates.push(...gameDated.slice(gameStart));

      // 마감 체인은 신청기간 셀 전체(시작→끝). gameStartIndex=length 라 sanity 는
      // 경기일에만 걸리고 여기엔 안 걸린다(달력 불가 날짜만 걸러짐).
      if (applyMds.length > 0) {
        const applyDated = inferYear(applyMds, applyMds.length, anchor, now);
        if (applyDated !== null) deadlines.push(applyDated[applyMds.length - 1]);
      }
      const div = cellText(divIdx);
      if (div) divisionCells.push(div);
    }
  }

  // 경기일을 하나도 못 얻으면 파싱 가드 실패(신청현황표 없음·전 행 추론실패).
  if (gameDates.length === 0) return null;
  gameDates.sort();
  const startDate = gameDates[0];
  const lastGameDate = gameDates[gameDates.length - 1];

  // 마감일은 행별 신청기간 마지막 날짜의 최댓값. 경기일보다 늦으면 원문 오류로 보고
  // 비운다(값을 지어내지 않는다 — gj 파서와 동일한 방어).
  let deadline: string | null = deadlines.length > 0
    ? deadlines.sort()[deadlines.length - 1]
    : null;
  if (deadline !== null && deadline > lastGameDate) deadline = null;

  return {
    title,
    startDate,
    endDate: lastGameDate !== startDate ? lastGameDate : null,
    deadline,
    divisionText: divisionCells.join(' '),
    posterUrl: root.querySelector('#bo_v_con img')?.getAttribute('src') ?? null,
    bodyText,
  };
}

export function buildTournament(
  item: ScheduleBoardItem,
  detail: ScheduleDetail,
  dict: DivisionDictRow[],
  region: string | null,
): CrawlerTournament {
  const { codes, label } = mapDivisionsByDict(detail.divisionText, dict);
  return {
    title: detail.title,
    start_date: detail.startDate,
    end_date: detail.endDate ?? undefined,
    application_deadline: detail.deadline ?? undefined,
    region: region ?? undefined,
    location: extractVenue(detail.bodyText) ?? undefined, // 기회적 — 본문이 포스터뿐이면 없음
    eligible_grades: codes,
    division_label_local: label || undefined,
    poster_url: detail.posterUrl ?? undefined,
    source_url: item.url,
    organizer: region ? `${region}테니스협회` : undefined, // 텍스트에 주최 없음 — region 폴백
    entry_fee: undefined, // 텍스트에 없음(포스터 이미지 안) — 포스터 추출 파이프라인 몫
  };
}

// =============================================================================
// listing 컨텐츠 해시 (서버 ETag 없을 때 변경 감지용)
// =============================================================================
async function listingContentHash(items: ScheduleBoardItem[]): Promise<string> {
  const stable = [
    `parser:${PARSER_REVISION}`,
    ...items.map((it) => `${it.wrId}|${it.title}`).sort(),
  ].join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stable));
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join(
    '',
  );
  return `W/"sha256:${hex}"`;
}

// =============================================================================
// parser entry point
// =============================================================================
export const gnuboard5ScheduleBoardParser: ParserFn = async (
  source: CrawlSource,
  ctx: ParserContext,
): Promise<CrawlResult> => {
  const empty = { fetched_count: 0, inserted_count: 0, updated_count: 0 };

  const org = source.org_code;
  if (!org) {
    return { ...empty, status: 'error', error: 'crawl_sources.org_code 미설정 — 추론 금지' };
  }

  // 1) listing fetch (conditional GET)
  let listHtml: string;
  let listEtag: string | null = null;
  let listLastModified: string | null = null;
  try {
    const headers: Record<string, string> = { ...COMMON_HEADERS };
    if (ctx.previousEtag) headers['If-None-Match'] = ctx.previousEtag;
    if (ctx.previousLastModified) headers['If-Modified-Since'] = ctx.previousLastModified;
    const res = await fetch(source.url, { headers });
    listEtag = res.headers.get('etag');
    listLastModified = res.headers.get('last-modified');
    if (res.status === 304) {
      return {
        ...empty,
        status: 'no_change',
        etag: listEtag ?? ctx.previousEtag ?? null,
        last_modified: listLastModified ?? ctx.previousLastModified ?? null,
      };
    }
    if (!res.ok) throw new Error(`listing fetch failed ${res.status}`);
    listHtml = await res.text();
  } catch (e) {
    return { ...empty, status: 'error', error: (e as Error).message };
  }

  // 2) parse listing
  let items: ScheduleBoardItem[];
  try {
    items = parseScheduleListing(listHtml, source.url);
  } catch (e) {
    return { ...empty, status: 'error', error: (e as Error).message };
  }

  // 목록이탈 만료 판정 기준 — "목록에 있음"을 상세 파싱 성공이 아니라 여기서 확정한다.
  await markListingSeen(ctx.audit, items.map((it) => it.url));

  // 3) content-hash 변경 감지 (서버 ETag 없을 때)
  const computedHash = await listingContentHash(items);
  const effectiveEtag = listEtag ?? computedHash;
  if (!listEtag && ctx.previousEtag && ctx.previousEtag === computedHash) {
    return {
      ...empty,
      status: 'no_change',
      etag: computedHash,
      last_modified: ctx.previousLastModified ?? null,
    };
  }

  // 4) 상세 처리 — 부서 사전은 crawl 당 1회 로드.
  const dict = await loadDivisionDict(ctx.audit.supabase, org);
  const now = new Date();
  const errors: string[] = [];
  let parseFailures = 0;

  for (const item of items.slice(0, DETAIL_CAP)) {
    try {
      const res = await fetch(item.url, { headers: COMMON_HEADERS });
      if (!res.ok) continue; // 보관할 원본 자체가 없음
      const html = await res.text();
      const detail = parseScheduleDetail(html, item.title, now);
      if (detail) {
        await upsertTournament(
          ctx.audit,
          'tennis',
          buildTournament(item, detail, dict, source.region),
          html,
        );
      } else {
        // 파싱 가드 미통과: 원본을 failed 로 보관해 파서 수정 후 재처리 가능하게 한다.
        await saveRawDocument(
          ctx.audit,
          item.url,
          html,
          null,
          'failed',
          '파싱 실패: 가드 미통과(신청현황표/경기일/연도추론)',
        );
        ctx.audit.fetched++;
        parseFailures++;
      }
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  const allFailed = parseFailures > 0 && ctx.audit.inserted + ctx.audit.updated === 0;
  if (allFailed) errors.push(`상세 ${parseFailures}건 모두 파싱 실패 — 사이트 구조 변경 의심`);

  // 전건 실패 시 변경감지 캐시를 null 로 비워 다음 실행이 no-change 로 조기종료하지
  // 않게 한다(gj 파서와 동일).
  return {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: ctx.audit.updated,
    status: allFailed ? 'error' : 'ok',
    error: errors.length > 0 ? errors.slice(0, 5).join('\n') : undefined,
    etag: allFailed ? null : effectiveEtag,
    last_modified: allFailed ? null : listLastModified,
  };
};
