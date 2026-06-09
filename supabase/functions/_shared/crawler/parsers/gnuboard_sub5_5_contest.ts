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
  extractGJDivisions,
  upsertTournament,
} from '../../crawler.ts';
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
function parseListing(html: string, baseUrl: string): BoardItem[] {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('failed to parse listing HTML');

  const items: BoardItem[] = [];
  const seen = new Set<string>();

  // sub5_2_2_view.php?sid= 가 있는 모든 a 태그
  const allLinks = dom.querySelectorAll('a[href]');
  for (const link of allLinks) {
    const el = link as unknown as {
      getAttribute(name: string): string | null;
      textContent: string;
    };
    const href = el.getAttribute('href') ?? '';
    if (!href.includes('sub5_2_2_view') || !href.includes('sid=')) continue;

    const title = (el.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;

    let absolute: string;
    try {
      absolute = new URL(href, baseUrl).toString();
    } catch {
      continue;
    }

    const sidMatch = absolute.match(/[?&]sid=(\d+)/);
    if (!sidMatch) continue;
    const sid = sidMatch[1];
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
async function fetchDetail(
  detailUrl: string,
  region: string,
  titleHint: string,
  org: 'gj' | 'jn',
): Promise<CrawlerTournament | null> {
  const res = await fetch(detailUrl, { headers: COMMON_HEADERS });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  // 제목: h3 우선, 없으면 listing 링크 텍스트(titleHint) 사용
  const h3El = dom.querySelector('h3');
  const title = (h3El?.textContent ?? '').replace(/\s+/g, ' ').trim() || titleHint;
  if (!title) return null;

  // 노이즈 태그 제거 후 body 텍스트 추출
  const bodyEl = dom.querySelector('body');
  if (bodyEl) {
    const noiseNodes = bodyEl.querySelectorAll(
      'script, style, nav, header, footer, aside, .gnb, .lnb, .snb',
    );
    for (const node of noiseNodes) {
      node.parentNode?.removeChild(node);
    }
  }
  const bodyText = (dom.querySelector('body')?.textContent ?? '').replace(/\s+/g, ' ').trim();

  // 대회일 추출: 가장 먼저 등장하는 유효 날짜를 start_date 로 사용
  const startDate = extractDate(bodyText) ?? extractDate(title);
  if (!startDate) return null;

  const { codes: gradeCodes, label: divisionLabel } = extractGJDivisions(
    `${title} ${bodyText}`,
    org,
  );

  const deadline = extractApplicationDeadline(bodyText) ?? undefined;

  // description: 메타데이터 헤더 + 원문 본문 (보일러플레이트 제거)
  const descParts: string[] = [];
  if (divisionLabel) descParts.push(`참가부서: ${divisionLabel}`);
  if (deadline) descParts.push(`신청마감: ${deadline}`);
  descParts.push(`대회일: ${startDate}`);
  if (region) descParts.push(`지역: ${region}`);
  const metaLine = descParts.join(' | ');

  // 원문에서 보일러플레이트 제거 후 본문 추출
  let rawBody = bodyText;

  // 하단 푸터 제거
  for (const marker of ['개인정보 취급방침', 'COPYRIGHT', '홈페이지바로가기']) {
    const idx = rawBody.indexOf(marker);
    if (idx > 0) rawBody = rawBody.substring(0, idx);
  }

  // 신청 폼 안내 보일러플레이트 제거 — 여러 변형 처리
  const formBoilerMarkers = [
    '참가신청 선수 변경시',
    '이점 참고하여 신중하게 신청 바랍니다',
  ];
  for (const marker of formBoilerMarkers) {
    const idx = rawBody.indexOf(marker);
    if (idx >= 0) {
      // 마커 이전 텍스트와 이후 텍스트를 분리
      const before = rawBody.substring(0, idx).trim();
      // 마커 이후에서 실제 공고 시작점 찾기 (『SPORTS 또는 제N회 등)
      const after = rawBody.substring(idx);
      const contentStart = after.search(/[『「]|제\d+회|풋\s*폴트|일\s*시\s+\d{4}년/);
      if (contentStart > 0) {
        rawBody = before + ' ' + after.substring(contentStart);
      } else {
        rawBody = before;
      }
    }
  }

  // 폼 테이블 헤더/잔해 제거 (참가부서 신청기간 경기일시 현재신청팀...)
  rawBody = rawBody
    .replace(/참가부서\s+신청기간\s+경기일시\s+현재신청팀\s+신청목록\s+신청하기\s+입금내역/g, '')
    .replace(/참가비\s+입금\s*×\s*팀?참가비\s+입금\s*×\s*\.?/g, '')
    .replace(/참가비\s+입금\s*×\s*\.?/g, '')
    .replace(/입금대기중을\s+클릭하여\s+입금계좌로\s+입금후로\s+입금일\s+입금자를\s+등록해주시기\s+바랍니다\.?/g, '')
    .replace(/\[신청대기\]/g, '')
    .replace(/\[신청마감\]/g, '')
    .replace(/\[신청중\]/g, '')
    // 사이트 네비/메뉴 잔해
    .replace(/선수회원신청\s*×?\s*대회일정.*?광주광역시테니스협회/g, '')
    .replace(/일상속\s*힐링운동.*?광주광역시테니스협회/g, '')
    .replace(/전문체육과\s*동호인이\s*함께하는/g, '')
    .replace(/대회일정\s+대회그룹\s+대회일정\s+대진표관리\s+대회결과\s+대회공지사항/g, '')
    .replace(/부서추후공지/g, '')
    .trim();

  // 메타 + 본문 결합 (본문이 실질적 내용을 포함할 때만)
  const contentBody = rawBody.length > metaLine.length + 50 ? rawBody : '';
  const description = contentBody
    ? `${metaLine}\n\n${contentBody}`
    : metaLine;

  return {
    title,
    description: description || undefined,
    start_date: startDate,
    application_deadline: deadline,
    region,
    eligible_grades: gradeCodes,
    division_label_local: divisionLabel,
    source_url: detailUrl,
    organizer: region ? `${region}테니스협회` : undefined,
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

  // 4) 상세 페이지 처리
  const org: 'gj' | 'jn' = source.slug.includes('gwangju') ? 'gj' : 'jn';
  const errors: string[] = [];
  for (const item of items.slice(0, 30)) {
    try {
      const detail = await fetchDetail(item.url, region, item.title, org);
      if (detail) {
        await upsertTournament(ctx.audit, 'tennis', detail);
      }
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  return {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: ctx.audit.updated,
    status: 'ok',
    error: errors.length > 0 ? errors.slice(0, 5).join('\n') : undefined,
    etag: effectiveEtag,
    last_modified: listing.lastModified ?? null,
  };
};
