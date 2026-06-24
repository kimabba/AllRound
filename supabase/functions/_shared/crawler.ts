import { SupabaseClient } from '@supabase/supabase-js';
import { serviceClient } from './supabase.ts';
import { regionCodeFromLabel } from './enums.ts';

export interface CrawlerTournament {
  title: string;
  organizer?: string;
  description?: string;
  start_date: string; // YYYY-MM-DD
  end_date?: string;
  application_deadline?: string;
  region?: string;
  location?: string;
  eligible_grades: string[]; // ['gj_m_gold','gj_m_general',...]
  division_label_local?: string; // '골드부 · 일반부' — UI 표시용
  entry_fee?: number;
  prize?: string;
  format?: string;
  regulation_fields?: Array<{ label: string; value: string }>;
  regulation_notes?: string[];
  regulation_body?: string;
  source_url: string;
}

export interface AuditHandle {
  id: string;
  source: string;
  supabase: SupabaseClient;
  fetched: number;
  inserted: number;
  updated: number;
}

export async function startAudit(source: string): Promise<AuditHandle> {
  const supabase = serviceClient();
  const { data, error } = await supabase
    .from('crawl_audit')
    .insert({ source, status: 'running' })
    .select('id')
    .single();
  if (error) throw new Error(`startAudit: ${error.message}`);
  return { id: data!.id, source, supabase, fetched: 0, inserted: 0, updated: 0 };
}

export async function finishAudit(
  audit: AuditHandle,
  status: 'success' | 'partial' | 'failed',
  error?: string,
) {
  await audit.supabase
    .from('crawl_audit')
    .update({
      status,
      fetched_count: audit.fetched,
      inserted_count: audit.inserted,
      updated_count: audit.updated,
      error: error ?? null,
      finished_at: new Date().toISOString(),
    })
    .eq('id', audit.id);
}

/**
 * raw HTML 을 crawl_documents(raw zone)에 보관.
 * (source, source_url) 기준 upsert — 같은 게시글은 1 row, 재크롤 시 덮어씀.
 * raw 보관은 부가 기능이므로 실패해도 크롤 파이프라인을 중단하지 않는다.
 */
async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export async function saveRawDocument(
  audit: AuditHandle,
  sourceUrl: string,
  rawHtml: string,
  tournamentId: string | null,
  parseStatus: 'parsed' | 'failed' | 'pending' = 'parsed',
  parseError?: string,
): Promise<void> {
  const contentHash = await sha256Hex(rawHtml);
  // 파싱 실패 등으로 tournamentId 가 없을 때, 같은 게시글이 과거에 파싱 성공해
  // 연결돼 있었다면 그 연결(tournament_id)을 끊지 않도록 기존 값을 보존한다.
  // (일시적 파싱 실패가 멀쩡한 대회와의 링크를 지우는 데이터 손상 방지)
  let finalTournamentId = tournamentId;
  if (finalTournamentId === null) {
    const { data: prev } = await audit.supabase
      .from('crawl_documents')
      .select('tournament_id')
      .eq('source', audit.source)
      .eq('source_url', sourceUrl)
      .maybeSingle();
    finalTournamentId = prev?.tournament_id ?? null;
  }
  const { error } = await audit.supabase
    .from('crawl_documents')
    .upsert(
      {
        source: audit.source,
        source_url: sourceUrl,
        raw_html: rawHtml,
        content_hash: contentHash,
        http_status: 200,
        fetched_at: new Date().toISOString(),
        tournament_id: finalTournamentId,
        parse_status: parseStatus,
        parse_error: parseError ?? null,
      },
      { onConflict: 'source,source_url' },
    );
  if (error) console.error(`saveRawDocument: ${error.message}`);
}

/**
 * source_url 기준 upsert. 신규는 status='draft' 로 들어가 관리자 승인 대기.
 *  (사이트 셀렉터가 깨지거나 등급/날짜 추출이 잘못된 false positive 가
 *   바로 사용자에게 노출되지 않도록 하는 안전 장치)
 *
 * 임베딩은 published 가 된 후에만 채워진다.
 */
export async function upsertTournament(
  audit: AuditHandle,
  sport: 'tennis' | 'futsal',
  t: CrawlerTournament,
  rawHtml?: string,
): Promise<'inserted' | 'updated' | 'skipped'> {
  audit.fetched++;
  // 한글 권역명 → region_code (서버사이드 지역 필터용). 미매칭이면 null.
  const regionCode = regionCodeFromLabel(t.region);
  const { data: existing } = await audit.supabase
    .from('tournaments')
    .select(
      'id, title, start_date, application_deadline, eligible_grades, region, manual_description',
    )
    .eq('source', audit.source)
    .eq('source_url', t.source_url)
    .maybeSingle();

  if (existing) {
    // 변경된 필드만 업데이트. description 이 undefined 면 기존 값 유지 (덮어쓰지 않음)
    const updatePayload: Record<string, unknown> = {
      title: t.title,
      organizer: t.organizer ?? null,
    };
    if (t.description !== undefined && !existing.manual_description) {
      updatePayload.description = t.description ?? null;
    }
    // 요강 정형 데이터 보존 처리 (P2⑥ 데이터 무결성):
    //   파서가 추출에 성공하면 해당 값을 undefined 가 아닌 값/빈배열로 채운다.
    //   일시적 파싱 미스(레이아웃 변형 등)로 추출이 비면 undefined 로 들어오는데,
    //   이때 컬럼을 payload 에서 제외해 기존 구조화 데이터를 null 로 지우지 않고
    //   보존한다. (값이 정의돼 있을 때만 set — description 의 manual_description
    //   가드와 동일 취지)
    if (t.regulation_fields !== undefined) {
      updatePayload.regulation_fields = t.regulation_fields;
    }
    if (t.regulation_notes !== undefined) {
      updatePayload.regulation_notes = t.regulation_notes;
    }
    if (t.regulation_body !== undefined) {
      updatePayload.regulation_body = t.regulation_body;
    }
    const { error } = await audit.supabase
      .from('tournaments')
      .update({
        ...updatePayload,
        start_date: t.start_date,
        end_date: t.end_date ?? null,
        application_deadline: t.application_deadline ?? null,
        region: t.region ?? null,
        region_code: regionCode,
        location: t.location ?? null,
        eligible_grades: t.eligible_grades,
        division_label_local: t.division_label_local ?? null,
        entry_fee: t.entry_fee ?? null,
        prize: t.prize ?? null,
        format: t.format ?? null,
      })
      .eq('id', existing.id);
    if (error) throw new Error(`upsertTournament update: ${error.message}`);
    if (rawHtml) await saveRawDocument(audit, t.source_url, rawHtml, existing.id, 'parsed');
    audit.updated++;
    return 'updated';
  }

  const { data: insertedRow, error } = await audit.supabase
    .from('tournaments')
    .insert({
      sport,
      title: t.title,
      organizer: t.organizer ?? null,
      description: t.description ?? null,
      start_date: t.start_date,
      end_date: t.end_date ?? null,
      application_deadline: t.application_deadline ?? null,
      region: t.region ?? null,
      region_code: regionCode,
      location: t.location ?? null,
      eligible_grades: t.eligible_grades,
      division_label_local: t.division_label_local ?? null,
      entry_fee: t.entry_fee ?? null,
      prize: t.prize ?? null,
      format: t.format ?? null,
      regulation_fields: t.regulation_fields ?? null,
      regulation_notes: t.regulation_notes ?? null,
      regulation_body: t.regulation_body ?? null,
      source: audit.source,
      source_url: t.source_url,
      status: 'draft',
    })
    .select('id')
    .single();
  if (error) throw new Error(`upsertTournament insert: ${error.message}`);
  if (rawHtml) {
    await saveRawDocument(audit, t.source_url, rawHtml, insertedRow?.id ?? null, 'parsed');
  }
  audit.inserted++;
  return 'inserted';
}

/**
 * 본문에서 첫 번째 유효한 날짜를 ISO yyyy-mm-dd 로 반환. 없으면 null.
 *
 * 매칭 우선순위:
 *   1) 한국어 형식 "YYYY년 M월 D일"  ← Korean 사이트가 가장 흔히 쓰는 형식
 *   2) 숫자 형식    "YYYY[.-/]MM[.-/]DD"
 *
 * 추가 sanity 검증:
 *   - 연도가 (현재 연도 - 1) ~ (현재 연도 + 5) 범위 밖이면 skip.
 *     예) 은행 계좌번호 "784902-01-022035" 가 일부 매치되어 "4902-01-02"
 *         로 들어가는 false positive 차단.
 *   - 월: 1~12, 일: 1~31 검증 (단순 범위. 윤년 등 정밀 검증은 생략).
 *
 * 매치가 있어도 sanity 실패면 다음 매치로 넘어가며, 모두 실패하면 null.
 */
export function extractDate(text: string): string | null {
  const nowYear = new Date().getUTCFullYear();
  const minYear = nowYear - 1;
  const maxYear = nowYear + 5;

  const candidates: Array<{ y: string; m: string; d: string }> = [];

  // 1) 한국어 — "YYYY년 M월 D일"
  const koreanRegex = /(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/g;
  for (const m of text.matchAll(koreanRegex)) {
    candidates.push({ y: m[1], m: m[2], d: m[3] });
  }

  // 2) 숫자 — "YYYY[.-/]MM[.-/]DD"
  const numericRegex = /(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/g;
  for (const m of text.matchAll(numericRegex)) {
    candidates.push({ y: m[1], m: m[2], d: m[3] });
  }

  for (const c of candidates) {
    const yi = Number(c.y);
    const mi = Number(c.m);
    const di = Number(c.d);
    if (yi < minYear || yi > maxYear) continue;
    if (mi < 1 || mi > 12) continue;
    if (di < 1 || di > 31) continue;
    return `${c.y}-${c.m.padStart(2, '0')}-${c.d.padStart(2, '0')}`;
  }
  return null;
}

/**
 * 본문에서 "신청 마감일" 또는 "접수 기간"을 찾아 마감일을 추출.
 * 패턴 우선순위:
 *   1. "신청마감|접수마감|신청기간|접수기간 ... YYYY[.-/]MM[.-/]DD" → 그 날짜
 *   2. "~ YYYY[.-/]MM[.-/]DD 까지" 또는 "YYYY[.-/]MM[.-/]DD 까지" → 그 날짜
 *   3. 못 찾으면 null (notify-cron 의 deadline 알림 미발송)
 */
export function extractApplicationDeadline(text: string): string | null {
  const cleaned = text.replace(/\s+/g, ' ');
  const nowYear = new Date().getUTCFullYear();
  const minYear = nowYear - 1;
  const maxYear = nowYear + 5;

  const sanitize = (y: string, m: string, d: string): string | null => {
    const yi = Number(y), mi = Number(m), di = Number(d);
    if (yi < minYear || yi > maxYear) return null;
    if (mi < 1 || mi > 12) return null;
    if (di < 1 || di > 31) return null;
    return `${y}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`;
  };

  // 1) 라벨 + 숫자 형식: "신청기간 ... 2026-04-01"
  const labelNumericRegex =
    /(?:신청\s*마감|접수\s*마감|신청\s*기간|접수\s*기간|마감일)[^0-9]{0,40}(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/;
  const m1 = cleaned.match(labelNumericRegex);
  if (m1) {
    const r = sanitize(m1[1], m1[2], m1[3]);
    if (r) return r;
  }

  // 2) 라벨 + 한국어 형식: "신청기간 ... 2026년 4월 1일"
  const labelKoreanRegex =
    /(?:신청\s*마감|접수\s*마감|신청\s*기간|접수\s*기간|마감일)[^0-9]{0,40}(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일/;
  const m1k = cleaned.match(labelKoreanRegex);
  if (m1k) {
    const r = sanitize(m1k[1], m1k[2], m1k[3]);
    if (r) return r;
  }

  // 3) "...까지" 형식: 숫자
  const untilRegex = /(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})\s*(?:까지|마감)/;
  const m2 = cleaned.match(untilRegex);
  if (m2) {
    const r = sanitize(m2[1], m2[2], m2[3]);
    if (r) return r;
  }

  // 4) "...까지" 형식: 한국어
  const untilKoreanRegex = /(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일\s*(?:까지|마감)/;
  const m2k = cleaned.match(untilKoreanRegex);
  if (m2k) {
    const r = sanitize(m2k[1], m2k[2], m2k[3]);
    if (r) return r;
  }

  return null;
}

/**
 * 본문에서 대회 장소(상세 경기장)를 추출. 없으면 null.
 *
 * 한국 협회 공고는 "장소:" 라벨 없이 본문 중간에 "○○테니스장"처럼 등장하는 경우가 많다.
 * (참가비는 신청 폼/JS 에만 있어 정적 파싱으로 추출 불가 → 다루지 않음)
 *
 * 전략:
 *   1) "장소|경기장|개최지|대회장" 라벨 뒤의 장소명 우선
 *   2) 없으면 본문 첫 "[가-힣]{2,}(테니스장|정구장|구장|체육관|코트장)" 매치
 *   false positive 방지: 2글자 이상 고유명 + 시설 접미사로 제한. status='draft' 검수로 추가 보정.
 */
export function extractVenue(text: string): string | null {
  const cleaned = text.replace(/\s+/g, ' ');
  const SUFFIX = '(?:테니스장|정구장|구장|체육관|코트장|스포츠타운)';

  // 1) "장 소" (공백 포함) 라벨 뒤 장소명
  const labeledSpaced = cleaned.match(
    new RegExp(
      `장\\s*소\\s*[:：]?\\s*([가-힣A-Za-z0-9·()（）\\s]{2,30}?(?:${SUFFIX}|외\\s*보조경기장))`,
    ),
  );
  if (labeledSpaced) {
    const v = labeledSpaced[1].replace(/\s+/g, '').trim();
    if (v.length >= 3) return v;
  }

  // 2) 라벨 + 장소명 (정상 공백 없는 경우)
  const labeled = cleaned.match(
    new RegExp(`(?:장소|경기장|개최지|대회장)\\s*[:：]?\\s*([가-힣A-Za-z0-9·]{2,30}?${SUFFIX})`),
  );
  if (labeled && labeled[1].trim().length >= 3) return labeled[1].trim();

  // 3) 본문 첫 시설명
  const bare = cleaned.match(new RegExp(`([가-힣A-Za-z0-9·]{2,}${SUFFIX})`));
  if (bare) return bare[1].trim();

  return null;
}

// =============================================================================
// 대회 요강 정형화 추출
//
// 협회 공고 원본은 MS-Word 내보내기 <table> 구조다. 라벨셀 + 값셀 행:
//   <tr><td><p><span>장 소</span></p></td>
//       <td colspan="2"><p><span>영암종합스포츠타운테니스장 …</span></p></td></tr>
// 이를 description 평문이 아니라 표에서 직접 구조화 추출해
// regulation_fields(순서 보존)/regulation_notes 로 저장한다.
//
// 타입 안전: deno-dom 노드를 any 로 받지 않고, 실제 사용하는 멤버만 가진
// 최소 구조 인터페이스(DomElementLike)로 좁혀서 다룬다.
// =============================================================================

/** 요강 라벨 화이트리스트 — 공백 정규화 후 기준값. */
const REGULATION_LABELS: ReadonlySet<string> = new Set([
  '장소',
  '주최',
  '주관',
  '후원',
  '협찬',
  '시상',
  '사용구',
  '경기방식',
  '진행방식',
  '참가자격',
  // '경기종목' 제외: 실원본에서 정의형 라벨이 아니라 "경기종목|경기일자|참가비"
  // 컬럼 헤더 행으로 등장해 잘못된 값("경기일자")을 캡처함. sport 필드로 이미 정형화됨.
]);

/**
 * deno-dom 노드에서 실제로 쓰는 멤버만 좁힌 최소 구조.
 *
 * deno-dom 의 querySelectorAll 은 NodeList<Element> 를 돌려주는데 인덱스 타입이
 * Node 로 느슨해 querySelectorAll 멤버를 보장하지 못한다. 그래서 문서/요소 자체는
 * querySelectorAll 만 요구하고, 거기서 나온 각 노드는 unknown 경계를 거쳐
 * 함수 내부에서 좁혀 사용한다. (프로젝트 규칙: 외부 DOM 노드는 좁혀서 사용)
 */
interface QueryableNode {
  querySelectorAll(selectors: string): ArrayLike<unknown>;
}

/** unknown DOM 노드가 textContent 를 가졌는지 좁히는 가드. */
function asTextNode(node: unknown): { textContent: string | null } | null {
  if (typeof node === 'object' && node !== null && 'textContent' in node) {
    return node as { textContent: string | null };
  }
  return null;
}

/** unknown DOM 노드가 querySelectorAll 을 가졌는지 좁히는 가드. */
function asQueryableNode(node: unknown): QueryableNode | null {
  if (
    typeof node === 'object' && node !== null && 'querySelectorAll' in node &&
    typeof (node as { querySelectorAll: unknown }).querySelectorAll === 'function'
  ) {
    return node as QueryableNode;
  }
  return null;
}

/** 라벨 매칭용: 내부 공백을 모두 제거. ("장 소" → "장소") */
function normalizeLabel(raw: string): string {
  return raw.replace(/\s+/g, '');
}

/** 값 셀용: 줄바꿈/연속 공백을 단일 공백으로 접고 트림. (내부 공백은 보존) */
function normalizeValue(raw: string): string {
  return raw.replace(/\s+/g, ' ').trim();
}

/** 한 <tr> 의 셀 텍스트 배열을 normalizeValue 한 결과로 반환. */
function rowCellTexts(row: QueryableNode): string[] {
  const cells = row.querySelectorAll('td');
  const out: string[] = [];
  for (let c = 0; c < cells.length; c++) {
    const cell = asTextNode(cells[c]);
    out.push(normalizeValue(cell?.textContent ?? ''));
  }
  return out;
}

/** 신청현황표 헤더 토큰 — 이 표는 라이브 카운트(63/192)라 본문에서 제외. */
const APPLICATION_TABLE_TOKENS = ['참가부서', '신청기간', '신청하기', '입금내역', '현재신청팀'];

/**
 * 콘텐츠표 안의 "알려진 컬럼 헤더 행" 첫 셀 라벨(공백 정규화 후).
 * 예: "경기종목 | 경기일자 | 참가비 입금계좌" 헤더 행. 바로 뒤 데이터 행이
 * 같은 정보를 담으므로 헤더 행은 본문에서 제외한다. (P2⑤ — 좁은 범위:
 * 첫 셀이 이 라벨인 다칸 행만 제외하고, 숫자 없는 일반 텍스트 행은 보존.)
 */
const CONTENT_HEADER_FIRST_LABELS: ReadonlySet<string> = new Set(['경기종목']);

/**
 * 콘텐츠 <table> 을 선택한다.
 *
 * 협회 공고는 보통 2개의 표를 가진다:
 *   - 신청현황표: 헤더가 "참가부서 | 신청기간 | 경기일시 | 현재신청팀 | …" 이고
 *     "63 / 192" 같은 라이브 신청 카운트를 담는다 → 요강 본문 대상 아님.
 *   - 콘텐츠표: 일시/장소/주최/시상내역/참가자격/접수마감 등 공고 본문.
 *
 * 선택 규칙:
 *   - 화이트리스트 라벨(장소/주최 등)을 첫 셀에 가장 많이 포함한 <table> 선택.
 *   - 단, 신청현황표 토큰(참가부서/신청기간/신청하기 …)을 헤더로 가진 표는 제외.
 *   - 후보가 없으면 null (요강 추출 자체를 skip).
 *
 * 이 표를 fields/body 추출의 공통 스코프로 써서 신청현황표 행 오캡처를 막는다.
 */
function findRegulationTable(doc: QueryableNode): QueryableNode | null {
  const tables = doc.querySelectorAll('table');
  let best: QueryableNode | null = null;
  let bestScore = 0;
  for (let i = 0; i < tables.length; i++) {
    const table = asQueryableNode(tables[i]);
    if (!table) continue;
    const rows = table.querySelectorAll('tr');
    let labelHits = 0;
    let applicationTokenHits = 0;
    for (let r = 0; r < rows.length; r++) {
      const row = asQueryableNode(rows[r]);
      if (!row) continue;
      const cells = rowCellTexts(row);
      if (cells.length === 0) continue;
      const firstLabel = normalizeLabel(cells[0]);
      if (REGULATION_LABELS.has(firstLabel)) labelHits++;
      for (const cell of cells) {
        const norm = normalizeLabel(cell);
        if (APPLICATION_TABLE_TOKENS.some((tok) => norm.includes(tok))) {
          applicationTokenHits++;
          break;
        }
      }
    }
    // 신청현황표(토큰 2개 이상)는 콘텐츠표 후보에서 제외.
    if (applicationTokenHits >= 2) continue;
    if (labelHits > bestScore) {
      bestScore = labelHits;
      best = table;
    }
  }
  return best;
}

/**
 * 콘텐츠표의 각 <tr> 를 순회하며, 첫 셀 라벨이 화이트리스트면 둘째 셀을 value 로 push.
 *
 * 규칙:
 *   - 콘텐츠표(findRegulationTable)로 스코프 → 신청현황표 행 오캡처 방지.
 *   - 원본 표 순서 보존.
 *   - 라벨 내부 공백 정규화 ("장 소" → "장소").
 *   - 빈 값 셀 / 중복 라벨(first-wins) 제외.
 */
export function extractRegulationFields(
  doc: QueryableNode,
): Array<{ label: string; value: string }> {
  const table = findRegulationTable(doc);
  if (!table) return [];
  const out: Array<{ label: string; value: string }> = [];
  const seen = new Set<string>();
  const rows = table.querySelectorAll('tr');
  for (let r = 0; r < rows.length; r++) {
    const row = asQueryableNode(rows[r]);
    if (!row) continue;
    const cells = rowCellTexts(row);
    if (cells.length < 2) continue;
    const label = normalizeLabel(cells[0]);
    if (!REGULATION_LABELS.has(label)) continue;
    if (seen.has(label)) continue;
    const value = cells[1];
    if (!value) continue; // 빈 값 셀 제외
    seen.add(label);
    out.push({ label, value });
  }
  return out;
}

/**
 * 콘텐츠표를 행 구조를 살려 "읽기 쉬운 완전 본문"으로 직렬화.
 *
 * regulation_fields(요약)·regulation_notes(※)·배너를 제외한 나머지 풍부한 내용
 * (일시/경기일정+입금계좌/시상내역/참가자격/접수마감/경기방식 등)을 담는다.
 *
 * 제외 행:
 *   (a) 첫 셀이 화이트리스트 라벨인 2칸 행 (= regulation_fields).
 *   (b) ※ 로 시작하는 행 (= regulation_notes).
 *   (c) 빈/공백뿐인 행.
 *   (d) 배너/홍보 행: 『』 포함, "Sports 7330", "풋 폴트", 또는 대회 title 과
 *       동일하거나 title 을 포함하는 행.
 *
 * 직렬화:
 *   - 2칸: "라벨: 값" (라벨 내부 공백 정규화 "일 시" → "일시").
 *   - 3칸: "셀1 | 셀2 | 셀3".
 *   - 1칸: 텍스트 그대로 (◈/◎/● 줄 등).
 *   - 그 외 N칸: " | " join.
 *   행을 "\n" 으로 join, trim, 12000자 cap. 내용 없으면 null.
 */
export function extractRegulationBody(
  doc: QueryableNode,
  title?: string,
): string | null {
  const table = findRegulationTable(doc);
  if (!table) return null;
  const titleNorm = normalizeLabel(title ?? '');
  const lines: string[] = [];
  const rows = table.querySelectorAll('tr');
  for (let r = 0; r < rows.length; r++) {
    const row = asQueryableNode(rows[r]);
    if (!row) continue;
    const cells = rowCellTexts(row);
    const nonEmpty = cells.filter((c) => c !== '');
    if (nonEmpty.length === 0) continue; // (c) 빈 행 제외

    const joinedForCheck = nonEmpty.join(' ');
    const firstLabel = normalizeLabel(cells[0] ?? '');

    // (b) ※ 노트 행 제외
    if (joinedForCheck.startsWith('※')) continue;

    // (d) 배너/홍보 행 제외
    if (
      joinedForCheck.includes('『') || joinedForCheck.includes('』') ||
      joinedForCheck.includes('Sports 7330') || joinedForCheck.includes('풋 폴트') ||
      (titleNorm.length > 0 &&
        (normalizeLabel(joinedForCheck) === titleNorm ||
          normalizeLabel(joinedForCheck).includes(titleNorm)))
    ) {
      continue;
    }

    // (a) 화이트리스트 2칸 라벨 행 제외 (값이 있는 정의형 행만)
    if (nonEmpty.length === 2 && cells.length >= 2 && REGULATION_LABELS.has(firstLabel)) {
      continue;
    }

    // (e) 알려진 컬럼 헤더 행 제외 — 첫 셀이 "경기종목" 등 헤더 라벨인 다칸 행만.
    //     바로 뒤 데이터 행이 같은 정보를 담으므로 헤더는 중복 노이즈다.
    //     (좁은 범위: "남자부 | 여자부" 같은 일반 텍스트 다칸 행은 보존)
    if (nonEmpty.length >= 2 && CONTENT_HEADER_FIRST_LABELS.has(firstLabel)) {
      continue;
    }

    // 직렬화
    let line: string;
    if (nonEmpty.length === 2 && cells.length >= 2 && cells[0] !== '' && cells[1] !== '') {
      // "라벨: 값" — 라벨 내부 공백 정규화
      line = `${firstLabel}: ${cells[1]}`;
    } else if (nonEmpty.length >= 3) {
      line = nonEmpty.join(' | ');
    } else {
      line = nonEmpty.join(' ');
    }
    line = line.trim();
    if (line) lines.push(line);
  }

  const body = lines.join('\n').trim();
  if (!body) return null;
  // 완전성 우선: 가장 긴 공고(영암 ~8.6k자, 경기방식·준수사항 포함)도 누락 없이
  // 담되 runaway 만 차단. regulation_body 는 임베딩 대상이 아니라(설명은 description)
  // 길이가 RAG 에 영향 없음.
  const MAX = 12000;
  return body.length > MAX ? body.slice(0, MAX).replace(/\s+\S*$/, '').trimEnd() + ' …' : body;
}

/** 노트 1건 정규화·검증 후 (중복 아니면) 수집기에 push. */
function pushNote(raw: string, notes: string[], seen: Set<string>): void {
  const note = raw.replace(/^※\s*/, '').replace(/\s+/g, ' ').trim();
  if (!note) return; // 빈 조각 제외
  if (note.length > 300) return; // 표/상금 run-on 잔해 차단
  // 섹션 제목이 ※ 로 시작해 노트로 잡히는 경우 제외.
  // (예: "제한사항", "대회운영에 관한 사항", "랭킹규정에 관한 사항")
  // — 짧은 명사구이며 헤더 어미(사항/규정)로 끝남. 길이 가드로 본문 포함
  //   노트("대회운영에 관한 사항 사무장 …", "… 운영 기금 팀당 6,000원")는 보존.
  if (note.length <= 20 && /(?:사항|규정)$/.test(note)) return;
  if (seen.has(note)) return; // 중복 제거
  seen.add(note);
  notes.push(note);
}

/**
 * bodyText 평문에서 "※" 안내문을 추출하는 폴백 구현.
 *
 * 한계: 표가 평문화되면 한 ※ 조각이 다음 ※ 까지의 표 텍스트를 통째로 삼켜
 * "우천 시 …장 소영암…주 최…" 같은 run-on 오염이 생긴다. 따라서 이 구현은
 * <p> 요소 경계를 못 쓰는 비-테이블 crawl source 용 폴백으로만 쓴다.
 */
function extractRegulationNotesFromText(bodyText: string): string[] {
  if (!bodyText.includes('※')) return [];
  const notes: string[] = [];
  const seen = new Set<string>();
  const parts = bodyText.split('※');
  // 첫 조각(parts[0])은 ※ 이전 서두이므로 건너뛴다.
  for (let i = 1; i < parts.length; i++) {
    pushNote(parts[i], notes, seen);
  }
  return notes;
}

/**
 * DOM 에서 "※" 안내문을 요소 경계 기준으로 추출.
 *
 * 원본은 MS-Word export 라 각 ※ 안내문이 독립된 <p> 요소다:
 *   <p><span>※ </span><span>우천 시 … 추후 안내</span></p>
 * 따라서 <p> 단위로 textContent 를 보면 요소 경계가 곧 노트 경계라, bodyText
 * 평문 split 에서 발생하던 표/상금표 run-on 오염이 원천적으로 없다.
 *
 * 규칙:
 *   - 각 <p> 의 textContent 를 트림 → "※" 로 시작하면 노트로 채택.
 *   - 한 <p> 안에 ※ 가 여러 개면 "※" 로 분할해 각각 push(드묾, 안전장치).
 *   - 선행 "※"/공백 제거·트림, dedupe, 빈/300자 초과 제외.
 *   - 폴백: <p> 에서 노트를 하나도 못 찾으면(비-테이블 source 등) doc 전체
 *     textContent 를 평문 split 하는 기존 로직으로 폴백.
 */
export function extractRegulationNotes(doc: QueryableNode): string[] {
  const notes: string[] = [];
  const seen = new Set<string>();
  const paragraphs = doc.querySelectorAll('p');
  for (let i = 0; i < paragraphs.length; i++) {
    const p = asTextNode(paragraphs[i]);
    if (!p) continue;
    const text = (p.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!text.startsWith('※')) continue;
    // 한 <p> 에 ※ 가 여러 개일 수 있으니 분할(첫 조각은 ※ 이전 = 빈 문자열).
    const segments = text.split('※');
    for (let s = 1; s < segments.length; s++) {
      pushNote(segments[s], notes, seen);
    }
  }
  if (notes.length > 0) return notes;

  // 폴백: <p> 기반으로 못 찾은 경우 doc 전체 평문에서 ※ split.
  const root = asTextNode(doc);
  const bodyText = (root?.textContent ?? '').replace(/\s+/g, ' ').trim();
  return extractRegulationNotesFromText(bodyText);
}

/**
 * 광주/전남 생활체육 협회 공고 텍스트에서 부서 코드 추출.
 * org: 'gj' | 'jn' — prefix로 사용됨 (예: 'gj_m_gold')
 *
 * 반환값:
 *   codes:  eligible_grades 에 저장할 {org}_{suffix} 코드 배열
 *   label:  division_label_local 에 저장할 한국어 표시 문자열 (예: "골드부 · 일반부")
 */
export function extractGJDivisions(
  text: string,
  org: 'gj' | 'jn',
): { codes: string[]; label: string } {
  const KEYWORD_MAP: Array<{ keywords: string[]; suffix: string; label: string }> = [
    { keywords: ['오픈부', '남자오픈', '오픈'], suffix: 'm_open', label: '오픈부' },
    { keywords: ['골드부', '골드'], suffix: 'm_gold', label: '골드부' },
    { keywords: ['남자일반부', '일반부', '남자일반'], suffix: 'm_general', label: '일반부' },
    { keywords: ['지도자부', '지도자'], suffix: 'm_instructor', label: '지도자부' },
    { keywords: ['마스터즈부', '마스터즈'], suffix: 'm_masters', label: '마스터즈부' },
    { keywords: ['남자신인부', '신인부', '신인'], suffix: 'm_rookie', label: '신인부' },
    { keywords: ['베테랑부', '베테랑'], suffix: 'm_veteran', label: '베테랑부' },
    { keywords: ['초급자부', '비입상자부', '초급자'], suffix: 'm_beginner', label: '초급자부' },
    { keywords: ['여자오픈부', '여자오픈'], suffix: 'w_open', label: '여자오픈부' },
    {
      keywords: ['우승자부', '여자우승자', '국화', '금배'],
      suffix: 'w_winner',
      label: '여자우승자부',
    },
    { keywords: ['여자신인부', '여자신인'], suffix: 'w_rookie', label: '여자신인부' },
    { keywords: ['부부부', '부부'], suffix: 'couple', label: '부부부' },
    { keywords: ['크로스'], suffix: 'cross', label: '크로스대회' },
  ];

  const foundCodes: string[] = [];
  const foundLabels: string[] = [];

  for (const entry of KEYWORD_MAP) {
    const matched = entry.keywords.some((kw) => text.includes(kw));
    if (matched) {
      foundCodes.push(`${org}_${entry.suffix}`);
      foundLabels.push(entry.label);
    }
  }

  // 아무것도 매칭 안 되면 오픈부+일반부를 기본으로
  if (foundCodes.length === 0) {
    foundCodes.push(`${org}_m_open`, `${org}_m_general`);
    foundLabels.push('오픈부', '일반부');
  }

  return { codes: foundCodes, label: foundLabels.join(' · ') };
}

/**
 * @deprecated extractGJDivisions 사용 권장.
 * 구 파서 호환용으로만 유지.
 */
export function extractTennisGradesFromText(_text: string): string[] {
  return [];
}
