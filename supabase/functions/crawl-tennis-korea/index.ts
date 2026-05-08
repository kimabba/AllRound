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

const SOURCE = 'tennis-korea';
const LIST_URL = Deno.env.get('CRAWL_TENNIS_KOREA_URL') ??
  'https://www.koreatennis.or.kr/board/tournament/list.do';

async function fetchListing(): Promise<{ url: string; title: string }[]> {
  const res = await fetch(LIST_URL, { headers: { 'User-Agent': 'MatchUpBot/1.0' } });
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
    items.push({ url: new URL(href, LIST_URL).toString(), title });
  }
  return items;
}

async function fetchDetail(url: string, fallbackTitle: string): Promise<CrawlerTournament | null> {
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

  // 지역 추출 시도
  const regionMatch = body.match(
    /(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주)/,
  );
  return {
    title,
    description: body.slice(0, 1500),
    start_date: startDate,
    application_deadline: extractApplicationDeadline(body) ?? undefined,
    region: regionMatch?.[1],
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
        const t = await fetchDetail(item.url, item.title);
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
