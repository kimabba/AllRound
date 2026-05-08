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

const SOURCE = 'tennis-gwangju';
const REGION = '광주';
const LIST_URL = Deno.env.get('CRAWL_TENNIS_GWANGJU_URL') ??
  'https://www.gjtennis.kr/board/list.php?bo_table=tournament';

/**
 * 광주테니스 협회 대회 공고 크롤러.
 *
 * 사이트 구조가 바뀌면 selector 만 조정하면 된다.
 * 게시판 a 태그를 모두 가져와 제목·날짜·상세 페이지 URL 을 수집한다.
 *
 * 등급/시상/참가비 등 상세는 상세 페이지를 fetch 해서 본문 텍스트에서 추출.
 */
async function fetchListing(): Promise<{ url: string; title: string }[]> {
  const res = await fetch(LIST_URL, {
    headers: { 'User-Agent': 'MatchUpBot/1.0 (+https://matchup.app)' },
  });
  if (!res.ok) throw new Error(`Listing fetch failed ${res.status}`);
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('Failed to parse listing HTML');

  const items: { url: string; title: string }[] = [];
  const links = dom.querySelectorAll('a[href*="wr_id"]');
  for (const link of links) {
    const el = link as unknown as { getAttribute(name: string): string | null; textContent: string };
    const href = el.getAttribute('href');
    const title = (el.textContent ?? '').trim();
    if (!href || !title) continue;
    const absolute = new URL(href, LIST_URL).toString();
    items.push({ url: absolute, title });
  }
  return items;
}

async function fetchDetail(detailUrl: string): Promise<CrawlerTournament | null> {
  const res = await fetch(detailUrl, {
    headers: { 'User-Agent': 'MatchUpBot/1.0' },
  });
  if (!res.ok) return null;
  const html = await res.text();
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;

  const title = (dom.querySelector('h1, .bo_v_tit, .title')?.textContent ?? '').trim();
  if (!title) return null;
  const bodyText = (dom.querySelector('#bo_v_atc, .view_content, article')?.textContent ?? '').trim();

  const startDate = extractDate(bodyText);
  if (!startDate) return null;

  const grades = extractTennisGradesFromText(bodyText);
  if (grades.length === 0) return null;

  return {
    title,
    description: bodyText.slice(0, 1500),
    start_date: startDate,
    application_deadline: extractApplicationDeadline(bodyText) ?? undefined,
    region: REGION,
    eligible_grades: grades,
    source_url: detailUrl,
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
        const detail = await fetchDetail(item.url);
        if (detail) await upsertTournament(audit, 'tennis', detail);
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
