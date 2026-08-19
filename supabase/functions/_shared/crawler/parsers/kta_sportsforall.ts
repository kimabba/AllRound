// _shared/crawler/parsers/kta_sportsforall.ts
//
// KTA(대한테니스협회) 생활체육대회(sportsForAll) 전국 목록 JSON parser.
//   - Listing: GET https://join.kortennis.or.kr/sportsForAll/sportsForAll_selList.json
//     ?cmptDtlGb=02&sidoCd=ALL&sigunguCd=ALL&cmptStat=&cmptNm=&type=4
//     &strDt=YYYY-MM-DD&endDt=YYYY-MM-DD&selectSize=N&cntGbn=0&pageIndex=P
//     응답: { totalpage, totalCount, list: [...] } — pageIndex 로 페이지네이션.
//   - Detail: POST https://join.kortennis.or.kr/sportsForAll/sportsForAll_selEventInfoList.json
//     body { cmptEvntCd } — 응답 list[0] 에 cmptPlace(장소)·cmptHost(주최)가 있고,
//     부서명은 entryFeeTxt/partAppl/awardTxt/contactUs 중 대회마다 다른 필드에 자유
//     텍스트로 섞여 나온다(예: "1. 개나리부 ... 2. 챌린저부 ..."). 넷 다 없으면 놓치므로
//     네 필드를 모두 이어붙여 매칭한다. cmptEvntCont(요강 본문 HTML)에는 협회가 올린
//     포스터 이미지가 <img> 로 박혀있다 — OCR 은 안 하고 첫 이미지 URL만 poster_url 로
//     남겨 검수 화면에서 사람이 직접 보게 한다. listing 에는 이 정보들이 전혀 없다 —
//     최초 버전이 이걸 놓쳐 location/eligible_grades 가 거의 다 비어 있었다
//     (실사용자 지적으로 발견, 2026-08-19 재파싱).
//   - 사람이 보는 상세 페이지: GET .../sportsForAllRellyInfo.do?cmptEvntCd={code}&dtlSt=Tab1
//     (source_url 로 저장 — 로그인 불필요, 클릭해서 볼 수 있는 실제 페이지)
//
// 실측 확인(2026-08-19):
//   - sidoCd 는 "대회 개최지"가 아니라 리그 소속 지사 분류로 보인다 — 특정 코드로
//     필터링하면 해당 지역에서 실제 열리는 대회(강원 등)까지 0건으로 나온다.
//     그래서 listing 은 항상 sidoCd=ALL 로 받고, region_code 유도는 upsertTournament 가
//     location/title 텍스트에서 하도록 맡긴다(직접 호출하지 않음. KATO와 동일 원칙).
//   - listing 의 dtlSt("종료" 포함 여부)로 종료 대회를 걸러 상세 fetch 를 스킵한다
//     (kato_openlist.ts 와 동일 — 종료 대회는 갱신할 이유가 없고 HTTP 도 아낀다).
//
// 규약(kato_openlist.ts/gnuboard_sub5_5_contest.ts 와 동일):
//   - org 는 crawl_sources.org_code('kta'), 추론 금지.
//   - region 은 crawl_sources.region(전국이라 null).
//   - listing 이 JSON API 라 서버 ETag 를 안 준다 — content-hash 로 no_change 판정.
//   - 상세 fetch 30건 cap(DETAIL_CAP, kato_openlist.ts 와 동일).

import { type CrawlerTournament, markListingSeen, upsertTournament } from '../../crawler.ts';
import { type DivisionDictRow, loadDivisionDict, mapDivisionsByDict } from '../divisions.ts';
import type { CrawlResult, CrawlSource, ParserContext, ParserFn } from '../types.ts';

const USER_AGENT = 'MatchUpBot/1.0 (+https://matchup.app)';
const COMMON_HEADERS: Record<string, string> = {
  'User-Agent': USER_AGENT,
  'Accept': 'application/json,*/*;q=0.8',
  'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
};
const JSON_HEADERS: Record<string, string> = {
  ...COMMON_HEADERS,
  'Content-Type': 'application/json',
};
const DETAIL_PAGE_URL = 'https://join.kortennis.or.kr/sportsForAll/sportsForAllRellyInfo.do';
const DETAIL_API_URL =
  'https://join.kortennis.or.kr/sportsForAll/sportsForAll_selEventInfoList.json';
const PAGE_CAP = 20; // totalpage 가 비정상적으로 크게 와도 무한루프 방지
const DETAIL_CAP = 30; // 상세 fetch 상한(kato_openlist.ts 와 동일)

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
  dtlSt: string | null; // "접수 중" / "진행 중" / "종료" 등
  placeNm: string | null;
  cmptEndDt: string | null; // "2026.10.05(월)"
}

interface KtaListResponse {
  totalpage: number;
  totalCount: number;
  list: KtaListRow[];
}

interface KtaEventDetailRow {
  cmptPlace: string | null; // 장소 — 값 뒤에 탭 문자가 여러 개 붙어 나온다
  cmptHost: string | null; // 주최
  // 부서명이 이 네 필드 중 어디에 나오는지 대회마다 다르다(실측: 경북영일만은
  // entryFeeTxt, 과천 토리아리배는 partAppl/awardTxt/contactUs, 태백산배는
  // contactUs 에만). 하나만 보면 놓치므로 넷 다 모아서 매칭한다.
  entryFeeTxt: string | null; // 참가비 안내
  partAppl: string | null; // 참가신청 안내
  awardTxt: string | null; // 시상내역
  contactUs: string | null; // 문의처
  cmptEvntCont: string | null; // 요강 본문 HTML — 협회가 올린 포스터 이미지가 <img> 로 박혀있다
}

interface KtaEventDetailResponse {
  code: string;
  list: KtaEventDetailRow[];
}

export interface KtaEventDetail {
  location: string | null;
  organizer: string | null;
  divisionText: string;
  posterUrl: string | null;
}

function buildDetailPageUrl(cmptEvntCd: string): string {
  const u = new URL(DETAIL_PAGE_URL);
  u.searchParams.set('cmptEvntCd', cmptEvntCd);
  u.searchParams.set('dtlSt', 'Tab1');
  return u.toString();
}

// 요강 본문 HTML에서 첫 포스터 이미지 URL만 뽑는다(OCR 안 함 — 관리자가 검수 화면에서
// 직접 보도록 URL만 남긴다). 상대경로(/upload/...)는 사이트 기준으로 절대경로화한다.
export function extractPosterUrl(html: string | null | undefined): string | null {
  if (!html) return null;
  const m = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  if (!m) return null;
  try {
    return new URL(m[1], 'https://join.kortennis.or.kr').toString();
  } catch {
    return null;
  }
}

// KTA 필드는 값 뒤에 탭/개행이 여러 개 붙어 나온다("포항시 뱃머리테니스장 외 보조경기장\t\t\t...").
function cleanField(v: string | null | undefined): string | null {
  const t = v?.replace(/[\t\r\n]+/g, ' ').trim();
  return t || null;
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
  ended: boolean;
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
      ended: (row.dtlSt ?? '').includes('종료'),
      url: buildDetailPageUrl(cmptEvntCd),
    });
  }
  return items;
}

// =============================================================================
// 상세 fetch — 장소/주최/부서 텍스트. listing 에는 이 정보가 없다.
// =============================================================================
export async function fetchEventDetail(cmptEvntCd: string): Promise<KtaEventDetail | null> {
  const res = await fetch(DETAIL_API_URL, {
    method: 'POST',
    headers: JSON_HEADERS,
    body: JSON.stringify({ cmptEvntCd }),
  });
  if (!res.ok) return null;
  const data = await res.json() as KtaEventDetailResponse;
  const row = data.list?.[0];
  if (!row) return null;
  const divisionText = [row.entryFeeTxt, row.partAppl, row.awardTxt, row.contactUs]
    .map((v) => cleanField(v) ?? '')
    .join(' ');
  return {
    location: cleanField(row.cmptPlace),
    organizer: cleanField(row.cmptHost),
    divisionText,
    posterUrl: extractPosterUrl(row.cmptEvntCont),
  };
}

// code 기준으로 합친다(중복 code 는 먼저 온 사전 우선) — kta+kato 사전을 함께 매칭할 때 씀.
export function mergeDivisionDicts(...dicts: DivisionDictRow[][]): DivisionDictRow[] {
  const byCode = new Map<string, DivisionDictRow>();
  for (const dict of dicts) {
    for (const row of dict) {
      if (!byCode.has(row.code)) byCode.set(row.code, row);
    }
  }
  return [...byCode.values()];
}

// =============================================================================
// listing 컨텐츠 해시 (서버 ETag 없을 때 변경 감지용) — kato_openlist.ts 와 동일 패턴
// =============================================================================
async function listingContentHash(items: KtaListItem[]): Promise<string> {
  const stable = items
    .map((it) =>
      `${it.cmptEvntCd}|${it.title}|${it.startDate}|${it.endDate ?? ''}|${
        it.applicationDeadline ?? ''
      }|${it.location ?? ''}|${it.ended}`
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
  detail: KtaEventDetail | null,
  dict: DivisionDictRow[],
  region: string | null,
): CrawlerTournament {
  // 부서명이 listing 에는 없고 상세 entryFeeTxt 안에 자유 텍스트로 섞여 있어,
  // title 과 이어붙여 매칭한다(gnuboard_sub5_5_contest.ts 의 title+body fallback 과 동일 원칙).
  const matchText = `${item.title} ${detail?.divisionText ?? ''}`;
  const { codes, label } = mapDivisionsByDict(matchText, dict);
  return {
    title: item.title,
    start_date: item.startDate,
    end_date: item.endDate ?? undefined,
    application_deadline: item.applicationDeadline ?? undefined,
    region: region ?? undefined,
    location: detail?.location ?? item.location ?? undefined,
    organizer: detail?.organizer ?? undefined,
    eligible_grades: codes,
    division_label_local: label || undefined,
    poster_url: detail?.posterUrl ?? undefined,
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

  // 목록이탈 만료 판정 기준 — 종료 여부와 무관하게 전체 URL 로 찍는다.
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

  // 3) 활성(비종료) 대회만 상세 fetch + upsert — 이미 끝난 대회는 갱신할 이유가
  // 없다(kato_openlist.ts 와 동일 원칙). 상세는 장소/주최/부서 텍스트를 채운다.
  const active = allItems.filter((it) => !it.ended);
  const toProcess = active.slice(0, DETAIL_CAP);
  // KTA 자체 사전(kta_m_open 등)은 실제 대회에서 거의 안 쓰인다 — 실측 2건(경북영일만/
  // 과천 토리아리배) 모두 KATO 부서명(개나리부/챌린저부/국화부)을 그대로 썼다.
  // KATO 사전도 함께 로드해 매칭한다.
  const dict = mergeDivisionDicts(
    await loadDivisionDict(ctx.audit.supabase, org),
    await loadDivisionDict(ctx.audit.supabase, 'kato'),
  );
  const errors: string[] = [];

  for (const item of toProcess) {
    try {
      const detail = await fetchEventDetail(item.cmptEvntCd);
      await upsertTournament(
        ctx.audit,
        'tennis',
        buildTournament(item, detail, dict, source.region),
      );
    } catch (e) {
      errors.push(`${item.url}: ${(e as Error).message}`);
    }
  }

  const allFailed = toProcess.length > 0 && errors.length === toProcess.length;

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
