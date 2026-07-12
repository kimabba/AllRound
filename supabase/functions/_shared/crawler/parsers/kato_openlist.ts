// _shared/crawler/parsers/kato_openlist.ts
//
// KATO (사)한국테니스발전협의회 대회일정 parser.
//   - Listing: /openList  (월별 대회 목록. 대회당 <table>)
//   - Detail:  /openGame/{seq}  (장소·주최·참가비 라벨표)
//
// 실측 구조(2026-07 확인):
//   목록 대회 블록 = <div.content-sector><table><tr>
//     td.group-sector(그룹 이미지) | td.title-sector(a.content-title 제목+링크,
//       span.parts 부서목록, div.date 날짜범위) | td.part-sector(span.com* 상태)
//   상태 class: comgray=종료 / comblue=접수중 / comdefault=준비중
//   상세: div.group-title(제목), <td>라벨</td><td colspan=2>값</td>
//     (라벨은 전각공백: '장 소' / '주 최' / '참가비')
//
// 규약(설계 docs/superpowers/specs/2026-07-11-p5-kato-grade-kb-and-parser-design.md ③):
//   - 종료(comgray) 대회는 상세 fetch·upsert 스킵(노이즈·HTTP 절약).
//   - 부서는 목록 span.parts 텍스트로 mapDivisionsByDict — 미매칭 시 codes=[](결정 A).
//   - application_deadline = null (KATO 미제공). start_date = 날짜범위 시작.
//   - org 는 crawl_sources.org_code('kato'), 추론 금지. 상세 fetch 30건 cap.

import { DOMParser } from 'deno-dom';
import { type CrawlerTournament, upsertTournament } from '../../crawler.ts';
import { type DivisionDictRow, loadDivisionDict, mapDivisionsByDict } from '../divisions.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};
const DETAIL_CAP = 30;

// deno-dom 요소를 최소 인터페이스로 좁혀 쓰기 위한 캐스트 헬퍼.
type El = {
  getAttribute(name: string): string | null;
  textContent: string;
  querySelector(sel: string): El | null;
  querySelectorAll(sel: string): ArrayLike<El> & Iterable<El>;
  nextElementSibling: El | null;
};

export type KatoStatus = 'ended' | 'open' | 'preparing' | 'unknown';

export interface KatoListItem {
  seq: string;
  url: string;
  title: string;
  partsText: string;
  startDate: string; // YYYY-MM-DD
  endDate: string | null;
  status: KatoStatus;
}

function classToStatus(cls: string): KatoStatus {
  if (cls.includes('comgray')) return 'ended';
  if (cls.includes('comblue')) return 'open';
  if (cls.includes('comdefault')) return 'preparing';
  return 'unknown';
}

// "2026.01.21 ~ 2026.01.25" → { start:'2026-01-21', end:'2026-01-25' }
function parseDateRange(text: string): { start: string | null; end: string | null } {
  const dates = [...text.matchAll(/(\d{4})\.(\d{1,2})\.(\d{1,2})/g)].map((m) => {
    const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
    if (y < 2024 || y > 2030 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return `${m[1]}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  }).filter((x): x is string => x !== null);
  if (dates.length === 0) return { start: null, end: null };
  return { start: dates[0], end: dates.length > 1 ? dates[dates.length - 1] : null };
}

// =============================================================================
// 목록 파싱 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export function parseKatoListing(html: string, baseUrl: string): KatoListItem[] {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) throw new Error('failed to parse KATO listing HTML');

  const items: KatoListItem[] = [];
  const seen = new Set<string>();
  const tables = (dom as unknown as El).querySelectorAll('table');
  for (const table of tables) {
    const a = table.querySelector('a.content-title');
    if (!a) continue;
    const href = a.getAttribute('href') ?? '';
    const seqMatch = href.match(/openGame\/(\w+)/);
    if (!seqMatch) continue;
    const seq = seqMatch[1];
    if (seen.has(seq)) continue;

    const title = (a.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;

    let url: string;
    try {
      url = new URL(href, baseUrl).toString();
    } catch {
      continue;
    }

    const partsText = (table.querySelector('span.parts')?.textContent ?? '')
      .replace(/\s+/g, ' ').trim();
    const dateText = (table.querySelector('.date')?.textContent ?? '').trim();
    const { start, end } = parseDateRange(dateText);
    if (!start) continue; // 날짜 없는 행(헤더/잡음)은 스킵
    const statusCls = table.querySelector('td.part-sector span')?.getAttribute('class') ?? '';

    seen.add(seq);
    items.push({
      seq,
      url,
      title,
      partsText,
      startDate: start,
      endDate: end,
      status: classToStatus(statusCls),
    });
  }
  return items;
}

// =============================================================================
// 상세 필드 추출 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export interface KatoDetailFields {
  title: string;
  location?: string;
  organizer?: string;
  entryFee?: number;
}

// 라벨 td(전각공백 무시) → 다음 td 값. 없으면 undefined.
function labelValue(dom: El, normalizedLabel: string): string | undefined {
  const tds = dom.querySelectorAll('td');
  for (const td of tds) {
    if ((td.textContent ?? '').replace(/\s+/g, '') === normalizedLabel) {
      const v = (td.nextElementSibling?.textContent ?? '').replace(/\s+/g, ' ').trim();
      return v || undefined;
    }
  }
  return undefined;
}

// 장소 값 뒤에 붙는 부서주석(▣/◈/▶/* 이후)은 잘라 위치만 남긴다.
function cleanVenue(v: string | undefined): string | undefined {
  if (!v) return undefined;
  const cut = v.split(/[▣◈▶*]/)[0].trim();
  return cut || undefined;
}

export function parseKatoDetail(html: string, titleHint: string): KatoDetailFields | null {
  const dom = new DOMParser().parseFromString(html, 'text/html');
  if (!dom) return null;
  const root = dom as unknown as El;

  const groupTitle = (root.querySelector('.group-title')?.textContent ?? '')
    .replace(/\s+/g, ' ').trim();
  const title = groupTitle || titleHint;
  if (!title) return null;

  const location = cleanVenue(labelValue(root, '장소'));
  const organizer = labelValue(root, '주최');

  let entryFee: number | undefined;
  const feeRaw = labelValue(root, '참가비');
  if (feeRaw) {
    const m = feeRaw.match(/([0-9][0-9,]*)\s*원/);
    if (m) {
      const amount = Number(m[1].replace(/,/g, ''));
      if (amount > 0 && amount < 1_000_000) entryFee = amount;
    }
  }
  return { title, location, organizer, entryFee };
}

// =============================================================================
// listing 컨텐츠 해시 (서버 ETag 없을 때 변경 감지용)
// =============================================================================
async function listingContentHash(items: KatoListItem[]): Promise<string> {
  // 날짜범위·부서목록도 해시에 포함 — 이 값이 바뀌면(seq/title/status 동일해도)
  // start_date/end_date/eligible_grades 가 stale 해지므로 no_change 로 넘기면 안 된다.
  const stable = items
    .map((it) =>
      `${it.seq}|${it.title}|${it.status}|${it.startDate}|${it.endDate ?? ''}|${it.partsText}`
    )
    .sort().join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stable));
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join(
    '',
  );
  return `W/"sha256:${hex}"`;
}

function buildTournament(
  item: KatoListItem,
  detail: KatoDetailFields,
  dict: DivisionDictRow[],
  region: string | null,
): CrawlerTournament {
  const { codes, label } = mapDivisionsByDict(item.partsText, dict);
  const descParts: string[] = [];
  if (item.partsText) descParts.push(`참가부서: ${item.partsText}`);
  descParts.push(`대회일: ${item.startDate}${item.endDate ? ` ~ ${item.endDate}` : ''}`);
  if (detail.location) descParts.push(`장소: ${detail.location}`);
  if (detail.organizer) descParts.push(`주최: ${detail.organizer}`);
  return {
    title: detail.title,
    description: descParts.join(' | ') || undefined,
    start_date: item.startDate,
    end_date: item.endDate ?? undefined,
    application_deadline: undefined, // KATO 미제공
    region: region ?? undefined,
    location: detail.location,
    eligible_grades: codes,
    division_label_local: label || undefined,
    source_url: item.url,
    organizer: detail.organizer,
    entry_fee: detail.entryFee,
  };
}

// =============================================================================
// parser entry point
// =============================================================================
export const katoOpenListParser: ParserFn = async (
  source: CrawlSource,
  ctx: ParserContext,
): Promise<CrawlResult> => {
  const empty = { fetched_count: 0, inserted_count: 0, updated_count: 0 };

  const org = source.org_code;
  if (!org) {
    return { ...empty, status: 'error', error: 'crawl_sources.org_code 미설정 — 추론 금지' };
  }

  // 1) listing fetch
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
  let items: KatoListItem[];
  try {
    items = parseKatoListing(listHtml, source.url);
  } catch (e) {
    return { ...empty, status: 'error', error: (e as Error).message };
  }

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

  // 4) 활성(비종료) 대회만 상세 처리
  const active = items.filter((it) => it.status !== 'ended');
  const dict = await loadDivisionDict(ctx.audit.supabase, org);
  const errors: string[] = [];
  let parseFailures = 0;

  for (const item of active.slice(0, DETAIL_CAP)) {
    try {
      const res = await fetch(item.url, { headers: COMMON_HEADERS });
      if (!res.ok) continue; // 원본 자체가 없음
      const html = await res.text();
      const detail = parseKatoDetail(html, item.title);
      if (detail) {
        await upsertTournament(
          ctx.audit,
          'tennis',
          buildTournament(item, detail, dict, source.region),
          html,
        );
      } else {
        ctx.audit.fetched++;
        parseFailures++;
      }
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  const allFailed = parseFailures > 0 && ctx.audit.inserted + ctx.audit.updated === 0;
  if (allFailed) errors.push(`상세 ${parseFailures}건 모두 파싱 실패 — 사이트 구조 변경 의심`);

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
