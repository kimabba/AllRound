// _shared/crawler/parsers/tennis_gwangju_board.ts
// 광주테니스 협회 게시판 parser. Phase 2 dispatcher 가 직접 호출한다.
//
// 기존 supabase/functions/crawl-tennis-gwangju/index.ts 로직을 1:1 보존:
//   - fetchListing: a[href*="wr_id"] 로 게시글 링크 수집
//   - fetchDetail: h1/.bo_v_tit/.title + #bo_v_atc/.view_content/article 본문
//   - 등급/날짜/마감일 추출은 _shared/crawler.ts 의 공통 헬퍼 사용
//   - 최대 30건만 처리 (기존과 동일)
//
// 변경점:
//   - audit start/finish 는 dispatcher 가 관리 → 이 모듈은 호출하지 않음
//   - 결과를 CrawlResult 로 반환 (fetched/inserted/updated 카운트)

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractTennisGradesFromText,
  upsertTournament,
} from '../../crawler.ts';
import type { CrawlResult, ParserFn } from '../types.ts';

const LIST_URL_DEFAULT = 'https://www.gjtennis.kr/board/list.php?bo_table=tournament';
const REGION_DEFAULT = '광주';

async function fetchListing(listUrl: string): Promise<{ url: string; title: string }[]> {
  const res = await fetch(listUrl, {
    headers: { 'User-Agent': 'MatchUpBot/1.0 (+https://matchup.app)' },
  });
  if (!res.ok) throw new Error(`Listing fetch failed ${res.status}`);
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('Failed to parse listing HTML');

  const items: { url: string; title: string }[] = [];
  const links = dom.querySelectorAll('a[href*="wr_id"]');
  for (const link of links) {
    const el = link as unknown as {
      getAttribute(name: string): string | null;
      textContent: string;
    };
    const href = el.getAttribute('href');
    const title = (el.textContent ?? '').trim();
    if (!href || !title) continue;
    const absolute = new URL(href, listUrl).toString();
    items.push({ url: absolute, title });
  }
  return items;
}

async function fetchDetail(
  detailUrl: string,
  region: string,
): Promise<CrawlerTournament | null> {
  const res = await fetch(detailUrl, {
    headers: { 'User-Agent': 'MatchUpBot/1.0' },
  });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  const title = (dom.querySelector('h1, .bo_v_tit, .title')?.textContent ?? '').trim();
  if (!title) return null;
  const bodyText = (dom.querySelector('#bo_v_atc, .view_content, article')?.textContent ?? '')
    .trim();

  const startDate = extractDate(bodyText);
  if (!startDate) return null;

  const grades = extractTennisGradesFromText(bodyText);
  if (grades.length === 0) return null;

  return {
    title,
    description: bodyText.slice(0, 1500),
    start_date: startDate,
    application_deadline: extractApplicationDeadline(bodyText) ?? undefined,
    region,
    eligible_grades: grades,
    source_url: detailUrl,
  };
}

export const tennisGwangjuBoardParser: ParserFn = async (source, ctx) => {
  const listUrl = source.url || LIST_URL_DEFAULT;
  const region = source.region ?? REGION_DEFAULT;
  const errors: string[] = [];
  let items: { url: string; title: string }[];
  try {
    items = await fetchListing(listUrl);
  } catch (e) {
    const result: CrawlResult = {
      fetched_count: 0,
      inserted_count: 0,
      updated_count: 0,
      status: 'error',
      error: (e as Error).message,
    };
    return result;
  }

  for (const item of items.slice(0, 30)) {
    try {
      const detail = await fetchDetail(item.url, region);
      if (detail) await upsertTournament(ctx.audit, 'tennis', detail);
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  const result: CrawlResult = {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: ctx.audit.updated,
    status: 'ok',
    error: errors.length > 0 ? errors.join('\n') : undefined,
  };
  return result;
};
