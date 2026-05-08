import { errorResponse, jsonResponse, preflight } from '../_shared/cors.ts';
import {
  CrawlerTournament,
  extractApplicationDeadline,
  extractDate,
  extractTennisGradesFromText,
  finishAudit,
  startAudit,
  upsertTournament,
} from '../_shared/crawler.ts';
import { DOMParser } from 'deno-dom';

const SOURCE = 'tennis-jeonnam';
const REGION = '전남';
const LIST_URL = Deno.env.get('CRAWL_TENNIS_JEONNAM_URL') ??
  'https://jntennis.or.kr/bbs/board.php?bo_table=tournament';

async function fetchListing(): Promise<{ url: string; title: string }[]> {
  const res = await fetch(LIST_URL, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
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
    items.push({ url: new URL(href, LIST_URL).toString(), title });
  }
  return items;
}

async function fetchDetail(url: string): Promise<CrawlerTournament | null> {
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
    region: REGION,
    eligible_grades: grades,
    source_url: url,
  };
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const audit = await startAudit(SOURCE);
  try {
    const items = await fetchListing();
    const errors: string[] = [];
    for (const item of items.slice(0, 30)) {
      try {
        const t = await fetchDetail(item.url);
        if (t) await upsertTournament(audit, 'tennis', t);
      } catch (e) {
        errors.push(`${item.url}: ${(e as Error).message}`);
      }
    }
    await finishAudit(audit, errors.length === 0 ? 'success' : 'partial', errors.join('\n'));
    return jsonResponse({
      source: SOURCE,
      fetched: audit.fetched,
      inserted: audit.inserted,
      updated: audit.updated,
      errors,
    });
  } catch (e) {
    await finishAudit(audit, 'failed', (e as Error).message);
    return errorResponse((e as Error).message, 500);
  }
});
