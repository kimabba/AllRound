// _shared/crawler/parsers/kta_sportsforall.ts
//
// KTA(대한테니스협회) 생활체육대회(sportsForAll) 전국 목록 JSON parser.
//   - Listing: GET https://join.kortennis.or.kr/sportsForAll/sportsForAll_selList.json
//     ?cmptDtlGb=02&sidoCd=ALL&sigunguCd=ALL&cmptStat=&cmptNm=&type=4
//     &strDt=YYYY-MM-DD&endDt=YYYY-MM-DD&selectSize=N&cntGbn=0&pageIndex=P
//     응답: { totalpage, totalCount, list: [...] } — pageIndex 로 페이지네이션.
//   - Detail: GET https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do
//     ?cmptEvntCd={code}&dtlSt=Tab1  (실측 확인, 2026-08-19. 로그인 불필요)
//
// 실측 확인(2026-08-19):
//   - sidoCd 는 "대회 개최지"가 아니라 리그 소속 지사 분류로 보인다 — 특정 코드로
//     필터링하면 해당 지역에서 실제 열리는 대회(강원 등)까지 0건으로 나온다.
//     그래서 listing 은 항상 sidoCd=ALL 로 받고, region_code 유도는 upsertTournament 가
//     location/title 텍스트에서 하도록 맡긴다(직접 호출하지 않음. KATO와 동일 원칙).
//   - listing JSON 에 부서(구분) 필드가 없다 — title 텍스트만으로 mapDivisionsByDict
//     시도. 대부분 unmapped(eligible_grades=[])로 남을 것으로 예상되며, 이는
//     "미매칭 시 codes=[] → draft 검수에서 보정" 기존 원칙과 동일하다(버그 아님).
//
// 규약(kato_openlist.ts/gnuboard_sub5_5_contest.ts 와 동일):
//   - org 는 crawl_sources.org_code('kta'), 추론 금지.
//   - region 은 crawl_sources.region(전국이라 null).
//   - listing 이 JSON API 라 서버 ETag 를 안 준다 — content-hash 로 no_change 판정.
//   - 상세 페이지 fetch 없음: listing 필드만으로 CrawlerTournament 조립 가능.

import { type CrawlerTournament, markListingSeen, upsertTournament } from '../../crawler.ts';
import { type DivisionDictRow, loadDivisionDict, mapDivisionsByDict } from '../divisions.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'application/json,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};
const DETAIL_BASE_URL = 'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do';
const PAGE_CAP = 20; // totalpage 가 비정상적으로 크게 와도 무한루프 방지

// =============================================================================
// KTA 응답 타입 (실측 JSON 기준, 2026-08-19)
// =============================================================================
interface KtaListRow {
  placeSeq: string | null;
  applEndDt: string | null; // "2026.09.30(수)"
  cmptEvntCd: string; // "202600202"
  cmptStrDt: string | null; // "2026.10.03(토)"
  cmptNm: string; // 대회명
  applStrDt: string | null;
  applCnt: string | null; // "0 / 0" — 미사용
  dtlSt: string | null; // "접수 중" 등 — 미사용(날짜기반 상태동기화에 위임)
  placeNm: string | null;
  cmptEndDt: string | null; // "2026.10.05(월)"
}

interface KtaListResponse {
  totalpage: number;
  totalCount: number;
  list: KtaListRow[];
}

function buildDetailUrl(cmptEvntCd: string): string {
  const u = new URL(DETAIL_BASE_URL);
  u.searchParams.set('cmptEvntCd', cmptEvntCd);
  u.searchParams.set('dtlSt', 'Tab1');
  return u.toString();
}

// =============================================================================
// 날짜 파싱 — "2026.10.03(토)" 처럼 요일 괄호가 붙어도, 숫자 그룹만 캡처하는
// 정규식이라 요일 부분은 애초에 매치 대상이 아니다(kato_openlist.ts parseDateRange 와
// 동일 원리).
// =============================================================================
export function parseKtaDate(text: string | null | undefined): string | null {
  if (!text) return null;
  const m = text.match(/(\d{4})\.(\d{1,2})\.(\d{1,2})/);
  if (!m) return null;
  const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  const nowYear = new Date().getUTCFullYear();
  if (y < nowYear - 1 || y > nowYear + 5) return null;
  if (mo < 1 || mo > 12) return null;
  if (d < 1 || d > 31) return null;
  return `${m[1]}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

// =============================================================================
// listing 파싱 (순수 함수 — 단위 테스트 가능). 한 페이지 분량의 row[] → 정규화.
// =============================================================================
export interface KtaListItem {
  cmptEvntCd: string;
  title: string;
  startDate: string; // YYYY-MM-DD
  endDate: string | null;
  applicationDeadline: string | null;
  location: string | null;
  url: string;
}

export function parseKtaListRows(rows: KtaListRow[]): KtaListItem[] {
  const items: KtaListItem[] = [];
  const seen = new Set<string>();
  for (const row of rows) {
    const cmptEvntCd = (row.cmptEvntCd ?? '').trim();
    if (!cmptEvntCd || seen.has(cmptEvntCd)) continue;
    const title = (row.cmptNm ?? '').replace(/\s+/g, ' ').trim();
    if (!title) continue;
    const startDate = parseKtaDate(row.cmptStrDt);
    if (!startDate) continue; // 날짜 없는 행은 스킵(kato_openlist.ts 와 동일 원칙)

    seen.add(cmptEvntCd);
    items.push({
      cmptEvntCd,
      title,
      startDate,
      endDate: parseKtaDate(row.cmptEndDt),
      applicationDeadline: parseKtaDate(row.applEndDt),
      location: row.placeNm?.trim() || null,
      url: buildDetailUrl(cmptEvntCd),
    });
  }
  return items;
}

// =============================================================================
// listing 컨텐츠 해시 (서버 ETag 없을 때 변경 감지용) — kato_openlist.ts 와 동일 패턴
// =============================================================================
async function listingContentHash(items: KtaListItem[]): Promise<string> {
  const stable = items
    .map((it) =>
      `${it.cmptEvntCd}|${it.title}|${it.startDate}|${it.endDate ?? ''}|${
        it.applicationDeadline ?? ''
      }|${it.location ?? ''}`
    )
    .sort()
    .join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(stable));
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join(
    '',
  );
  return `W/"sha256:${hex}"`;
}

// =============================================================================
// CrawlerTournament 조립 (순수 함수 — 단위 테스트 가능)
// =============================================================================
export function buildTournament(
  item: KtaListItem,
  dict: DivisionDictRow[],
  region: string | null,
): CrawlerTournament {
  const { codes, label } = mapDivisionsByDict(item.title, dict);
  return {
    title: item.title,
    start_date: item.startDate,
    end_date: item.endDate ?? undefined,
    application_deadline: item.applicationDeadline ?? undefined,
    region: region ?? undefined,
    location: item.location ?? undefined,
    eligible_grades: codes,
    division_label_local: label || undefined,
    source_url: item.url,
  };
}

// =============================================================================
// 페이지네이션 fetch — pageIndex 를 바꿔가며 totalpage 까지 순회
// =============================================================================
async function fetchPage(baseUrl: string, pageIndex: number): Promise<KtaListResponse> {
  const u = new URL(baseUrl);
  u.searchParams.set('pageIndex', String(pageIndex));
  const res = await fetch(u.toString(), { headers: COMMON_HEADERS });
  if (!res.ok) throw new Error(`KTA listing fetch failed ${res.status} (page ${pageIndex})`);
  return await res.json() as KtaListResponse;
}

// =============================================================================
// parser entry point
// =============================================================================
export const ktaSportsForAllParser: ParserFn = async (
  source: CrawlSource,
  ctx: ParserContext,
): Promise<CrawlResult> => {
  const empty = { fetched_count: 0, inserted_count: 0, updated_count: 0 };

  const org = source.org_code;
  if (!org) {
    return { ...empty, status: 'error', error: 'crawl_sources.org_code 미설정 — 추론 금지' };
  }

  // 1) 전 페이지 fetch
  let allItems: KtaListItem[];
  try {
    const first = await fetchPage(source.url, 1);
    const rows: KtaListRow[] = [...(first.list ?? [])];
    const totalPages = Math.min(first.totalpage ?? 1, PAGE_CAP);
    for (let p = 2; p <= totalPages; p++) {
      const page = await fetchPage(source.url, p);
      rows.push(...(page.list ?? []));
    }
    allItems = parseKtaListRows(rows);
  } catch (e) {
    return { ...empty, status: 'error', error: (e as Error).message };
  }

  // 목록이탈 만료 판정 기준 — 필터링 전 전체 URL 로 찍는다.
  await markListingSeen(ctx.audit, allItems.map((it) => it.url));

  // 2) content-hash 변경 감지 (JSON API 는 서버 ETag 를 안 준다)
  const computedHash = await listingContentHash(allItems);
  if (ctx.previousEtag && ctx.previousEtag === computedHash) {
    return {
      ...empty,
      status: 'no_change',
      etag: computedHash,
      last_modified: ctx.previousLastModified ?? null,
    };
  }

  // 3) upsert — 상세 fetch 불필요(listing 에 필요한 필드가 다 있음)
  const dict = await loadDivisionDict(ctx.audit.supabase, org);
  const errors: string[] = [];
  for (const item of allItems) {
    try {
      await upsertTournament(ctx.audit, 'tennis', buildTournament(item, dict, source.region));
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  const allFailed = allItems.length > 0 && errors.length === allItems.length;

  return {
    fetched_count: ctx.audit.fetched,
    inserted_count: ctx.audit.inserted,
    updated_count: ctx.audit.updated,
    status: allFailed ? 'error' : 'ok',
    error: errors.length > 0 ? errors.slice(0, 5).join('\n') : undefined,
    etag: allFailed ? null : computedHash,
    last_modified: null,
  };
};
