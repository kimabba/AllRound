// _shared/crawler/parsers/gnuboard_sub5_5_contest.ts
//
// 광주/전남 협회 "대회공지사항" (sub5_5.php?mo_board_id=contest_2) 통합 parser.
//
// 배경:
//   광주/전남 모두 동일한 그누보드 변형 템플릿을 사용하며, 2026 사이트
//   리뉴얼 이후 게시판 경로가 /board/list.php?bo_table=tournament → /sub5_5.php
//   로 변경되었다. 두 사이트의 listing/detail HTML 구조가 동일하므로
//   parser 한 개로 처리한다. region 은 crawl_sources.region 으로 구분.
//
// 변경 감지:
//   해당 사이트는 ETag/Last-Modified 응답 헤더를 내보내지 않는다.
//   대신 listing 의 (sid|title) 목록을 정렬·해시한 값을 last_etag 컬럼에
//   `W/"sha256:..."` 형태로 저장해 동일 listing 일 때 304-동급으로 처리한다.
//   서버측 헤더가 있으면 그것을 우선 사용 (forward compatibility).
//
// 보안 / 안정성:
//   - User-Agent 명시 (운영자 식별 가능)
//   - listing 30건 cap (기존 parser 와 동일 가용성 보호)
//   - 본문 추출 실패시 description 만 비우고 진행 (전체 fail 회피)
//   - upsert 시 status='draft' 로 들어가 어드민 승인 게이트 통과 필수
//     → 셀렉터 변경/오추출이 사용자에게 바로 노출되지 않음.

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractTennisGradesFromText,
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
  // 직전 응답이 서버 ETag (정상 RFC 형식) 였다면 If-None-Match 로 검증 요청.
  // 우리가 생성한 content-hash ETag (W/"sha256:...") 도 그대로 보낸다 — 서버는
  // 모르는 값으로 200 응답하므로 안전. 응답 본문 해시와 비교해 no_change 처리.
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
// listing 파싱
// =============================================================================
function parseListing(html: string, baseUrl: string): BoardItem[] {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('failed to parse listing HTML');

  const items: BoardItem[] = [];
  const seen = new Set<string>();

  // sid= 파라미터가 있는 a 태그가 게시글 상세 링크.
  // q_mode=view 대신 sid= 로 매칭 — raw '&' 미인코딩 URL 을 deno-dom 이
  // 엔티티로 오해할 때 q_mode 부분이 잘려 셀렉터가 매칭 안 되는 버그 회피.
  // gjtennis/jntennis 모두 동일 패턴.
  const allLinks = dom.querySelectorAll('a[href]');
  for (const link of allLinks) {
    const el = link as unknown as {
      getAttribute(name: string): string | null;
      textContent: string;
    };
    const href = el.getAttribute('href') ?? '';
    // sid= 파라미터 + q_mode 또는 view 키워드가 있는 링크만 처리
    if (!href.includes('sid=')) continue;
    if (!href.includes('q_mode') && !href.includes('view')) continue;

    const title = (el.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;

    let absolute: string;
    try {
      absolute = new URL(href, baseUrl).toString();
    } catch {
      continue;
    }

    // sid 추출 (안정 dedupe key)
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
// listing 의 컨텐츠 해시 (서버가 ETag 안 줄 때 변경 감지용)
//
// 안정 키: 정렬된 "sid|title" join → sha256 hex.
// page 번호, 검색 파라미터 등 변동 요소는 제외.
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
  // Weak ETag 형식 — 서버가 준 strong ETag 와 구분 가능
  return `W/"sha256:${hex}"`;
}

// =============================================================================
// 상세 페이지 fetch + 정규화
// =============================================================================
async function fetchDetail(
  detailUrl: string,
  region: string,
): Promise<CrawlerTournament | null> {
  const res = await fetch(detailUrl, { headers: COMMON_HEADERS });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  // 제목: ntb-tb-view 의 thead > th.r_none 이 정규 위치.
  // fallback 으로 h1/.bo_v_tit/.title 도 본다 (다른 게시판 변형 대비).
  const titleEl = dom.querySelector('table.ntb-tb-view th.r_none') ??
    dom.querySelector('h1') ??
    dom.querySelector('.bo_v_tit') ??
    dom.querySelector('.title');
  const title = (titleEl?.textContent ?? '').replace(/\s+/g, ' ').trim();
  if (!title) return null;

  // 본문: .content-area 가 신규 템플릿의 본문 컨테이너.
  // fallback: 옛 그누보드 selector + article/main.
  const bodyEl = dom.querySelector('.content-area') ??
    dom.querySelector('#bo_v_atc') ??
    dom.querySelector('.view_content') ??
    dom.querySelector('.bo_v_con') ??
    dom.querySelector('article') ??
    dom.querySelector('main');
  const bodyText = (bodyEl?.textContent ?? '').replace(/\s+/g, ' ').trim();

  // 날짜는 본문 + 제목 모두에서 시도. 없으면 skip
  // (이미지로만 공지하는 케이스를 false-positive 로 insert 하지 않기 위함).
  const startDate = extractDate(bodyText) ?? extractDate(title);
  if (!startDate) return null;

  // 등급도 본문 + 제목에서 추출. 비어 있어도 일단 진행 (admin 이 거를 수 있도록 draft 로 입력).
  const grades = extractTennisGradesFromText(`${title} ${bodyText}`);

  return {
    title,
    description: bodyText ? bodyText.slice(0, 1500) : undefined,
    start_date: startDate,
    application_deadline: extractApplicationDeadline(bodyText) ?? undefined,
    region,
    eligible_grades: grades,
    source_url: detailUrl,
    organizer: regionToOrganizer(region),
  };
}

function regionToOrganizer(region: string): string | undefined {
  if (!region) return undefined;
  return `${region}테니스협회`;
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

  // 서버측 304
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
    // 정상 200 이지만 항목 0 — 셀렉터 문제일 수 있어 error 가 아닌 ok 로 보고
    // (운영자가 last_fetched_count=0 추세로 감지). hash 도 계산해 다음 호출에서
    // 304-동급 처리 가능하게 한다.
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

  // 3) 서버 ETag 없을 때 content-hash 로 변경 감지
  const computedHash = await listingContentHash(items);
  const effectiveEtag = listing.etag ?? computedHash;
  if (
    !listing.etag &&
    ctx.previousEtag &&
    ctx.previousEtag === computedHash
  ) {
    // 본문은 받았지만 항목이 동일 → 상세 fetch 생략 (rate-limit / 트래픽 보호)
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
  const errors: string[] = [];
  for (const item of items.slice(0, 30)) {
    try {
      const detail = await fetchDetail(item.url, region);
      if (detail) {
        await upsertTournament(ctx.audit, 'tennis', detail);
      } else {
        // detail 이 null 인 케이스 (날짜/제목 없음) 는 audit.fetched 에도 안 잡힘.
        // 의도적: 노이즈를 줄이고 실제 후보만 카운트.
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
