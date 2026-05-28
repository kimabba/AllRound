import { SupabaseClient } from '@supabase/supabase-js';
import { serviceClient } from './supabase.ts';

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
): Promise<'inserted' | 'updated' | 'skipped'> {
  audit.fetched++;
  const { data: existing } = await audit.supabase
    .from('tournaments')
    .select('id, title, start_date, application_deadline, eligible_grades, region')
    .eq('source', audit.source)
    .eq('source_url', t.source_url)
    .maybeSingle();

  if (existing) {
    // 변경된 필드만 업데이트. description 이 undefined 면 기존 값 유지 (덮어쓰지 않음)
    const updatePayload: Record<string, unknown> = {
      title: t.title,
      organizer: t.organizer ?? null,
    };
    if (t.description !== undefined) updatePayload.description = t.description ?? null;
    const { error } = await audit.supabase
      .from('tournaments')
      .update({
        ...updatePayload,
        start_date: t.start_date,
        end_date: t.end_date ?? null,
        application_deadline: t.application_deadline ?? null,
        region: t.region ?? null,
        location: t.location ?? null,
        eligible_grades: t.eligible_grades,
        division_label_local: t.division_label_local ?? null,
        entry_fee: t.entry_fee ?? null,
        prize: t.prize ?? null,
        format: t.format ?? null,
      })
      .eq('id', existing.id);
    if (error) throw new Error(`upsertTournament update: ${error.message}`);
    audit.updated++;
    return 'updated';
  }

  const { error } = await audit.supabase.from('tournaments').insert({
    sport,
    title: t.title,
    organizer: t.organizer ?? null,
    description: t.description ?? null,
    start_date: t.start_date,
    end_date: t.end_date ?? null,
    application_deadline: t.application_deadline ?? null,
    region: t.region ?? null,
    location: t.location ?? null,
    eligible_grades: t.eligible_grades,
    division_label_local: t.division_label_local ?? null,
    entry_fee: t.entry_fee ?? null,
    prize: t.prize ?? null,
    format: t.format ?? null,
    source: audit.source,
    source_url: t.source_url,
    status: 'draft',
  });
  if (error) throw new Error(`upsertTournament insert: ${error.message}`);
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
