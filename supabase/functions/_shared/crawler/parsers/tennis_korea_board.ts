// _shared/crawler/parsers/tennis_korea_board.ts
// 한국테니스 협회 게시판 parser. Phase 2 dispatcher 가 직접 호출한다.
//
// 기존 supabase/functions/crawl-tennis-korea/index.ts 로직을 1:1 보존:
//   - 리스트: a[href*="view"], a[href*="board"] (title.length >= 4 만)
//   - 본문: .view_content, .board_view, article, main
//   - 지역은 본문에서 17개 광역 시·도 키워드로 추출 (없으면 undefined)

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractTennisGradesFromText,
  upsertTournament,
} from '../../crawler.ts';
import type { CrawlResult, ParserFn } from '../types.ts';

const LIST_URL_DEFAULT = 'https://www.koreatennis.or.kr/board/tournament/list.do';

async function fetchListing(listUrl: string): Promise<{ url: string; title: string }[]> {
  const res = await fetch(listUrl, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
  if (!res.ok) throw new Error(`Listing fetch failed ${res.status}`);
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('parse listing');

  const items: { url: string; title: string }[] = [];
  for (const link of dom.querySelectorAll('a[href*="view"], a[href*="board"]')) {
    const el = link as unknown as { getAttribute(n: string): string | null; textContent: string };
    const href = el.getAttribute('href');
    const title = (el.textContent ?? '').trim();
    if (!href || title.length < 4) continue;
    items.push({ url: new URL(href, listUrl).toString(), title });
  }
  return items;
}

async function fetchDetail(
  url: string,
  fallbackTitle: string,
  fallbackRegion: string | null,
): Promise<CrawlerTournament | null> {
  const res = await fetch(url, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  const title = (dom.querySelector('h1, h2, .title, .view_title')?.textContent ?? fallbackTitle)
    .trim();
  const body = (dom.querySelector('.view_content, .board_view, article, main')?.textContent ?? '')
    .trim();
  if (!title || !body) return null;

  const startDate = extractDate(body);
  if (!startDate) return null;
  const grades = extractTennisGradesFromText(body);
  if (grades.length === 0) return null;

  // 지역 추출 시도 — 본문 매치가 우선, 없으면 source.region(보통 null) 사용
  const regionMatch = body.match(
    /(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)/,
  );
  return {
    title,
    description: body.slice(0, 1500),
    start_date: startDate,
    application_deadline: extractApplicationDeadline(body) ?? undefined,
    region: regionMatch?.[1] ?? fallbackRegion ?? undefined,
    eligible_grades: grades,
    source_url: url,
  };
}

export const tennisKoreaBoardParser: ParserFn = async (source, ctx) => {
  const listUrl = source.url || LIST_URL_DEFAULT;
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
      const t = await fetchDetail(item.url, item.title, source.region);
      if (t) await upsertTournament(ctx.audit, 'tennis', t);
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
