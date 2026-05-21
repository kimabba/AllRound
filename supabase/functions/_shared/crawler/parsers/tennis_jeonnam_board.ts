// _shared/crawler/parsers/tennis_jeonnam_board.ts
// 전남테니스 협회 게시판 parser. Phase 2 dispatcher 가 직접 호출한다.
//
// 기존 supabase/functions/crawl-tennis-jeonnam/index.ts 로직을 1:1 보존.

import { DOMParser } from 'deno-dom';
import {
  type CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractTennisGradesFromText,
  upsertTournament,
} from '../../crawler.ts';
import type { CrawlResult, ParserFn } from '../types.ts';

const LIST_URL_DEFAULT = 'https://jntennis.or.kr/bbs/board.php?bo_table=tournament';
const REGION_DEFAULT = '전남';

async function fetchListing(listUrl: string): Promise<{ url: string; title: string }[]> {
  const res = await fetch(listUrl, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
  if (!res.ok) throw new Error(`Listing fetch failed ${res.status}`);
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('parse listing');

  const items: { url: string; title: string }[] = [];
  for (const link of dom.querySelectorAll('a[href*="wr_id"]')) {
    const el = link as unknown as { getAttribute(n: string): string | null; textContent: string };
    const href = el.getAttribute('href');
    const title = (el.textContent ?? '').trim();
    if (!href || !title) continue;
    items.push({ url: new URL(href, listUrl).toString(), title });
  }
  return items;
}

async function fetchDetail(url: string, region: string): Promise<CrawlerTournament | null> {
  const res = await fetch(url, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  const title = (dom.querySelector('h1, .bo_v_tit, .title')?.textContent ?? '').trim();
  const body = (dom.querySelector('#bo_v_atc, .view_content, article')?.textContent ?? '').trim();
  if (!title) return null;

  const startDate = extractDate(body);
  if (!startDate) return null;
  const grades = extractTennisGradesFromText(body);
  if (grades.length === 0) return null;

  return {
    title,
    description: body.slice(0, 1500),
    start_date: startDate,
    application_deadline: extractApplicationDeadline(body) ?? undefined,
    region,
    eligible_grades: grades,
    source_url: url,
  };
}

export const tennisJeonnamBoardParser: ParserFn = async (source, ctx) => {
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
      const t = await fetchDetail(item.url, region);
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
