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
  eligible_grades: string[]; // ['rookie','div5',...]
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
    // 변경된 필드만 업데이트 (전체 비교 생략하고 항상 업데이트)
    const { error } = await audit.supabase
      .from('tournaments')
      .update({
        title: t.title,
        organizer: t.organizer ?? null,
        description: t.description ?? null,
        start_date: t.start_date,
        end_date: t.end_date ?? null,
        application_deadline: t.application_deadline ?? null,
        region: t.region ?? null,
        location: t.location ?? null,
        eligible_grades: t.eligible_grades,
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
    entry_fee: t.entry_fee ?? null,
    prize: t.prize ?? null,
    format: t.format ?? null,
    source: audit.source,
    source_url: t.source_url,
    status: 'draft', // 관리자 승인 대기 (어드민 화면 SSF-272 후 일괄 승인)
  });
  if (error) throw new Error(`upsertTournament insert: ${error.message}`);
  audit.inserted++;
  return 'inserted';
}

/**
 * "YYYY[.-/]MM[.-/]DD" 형태의 첫 매치를 ISO yyyy-mm-dd 로 반환. 없으면 null.
 */
export function extractDate(text: string): string | null {
  const m = text.match(/(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/);
  if (!m) return null;
  const [, y, mm, dd] = m;
  return `${y}-${mm.padStart(2, '0')}-${dd.padStart(2, '0')}`;
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

  const labelRegex =
    /(?:신청\s*마감|접수\s*마감|신청\s*기간|접수\s*기간|마감일)[^0-9]{0,40}(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})/;
  const m1 = cleaned.match(labelRegex);
  if (m1) return `${m1[1]}-${m1[2].padStart(2, '0')}-${m1[3].padStart(2, '0')}`;

  const untilRegex = /(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})\s*(?:까지|마감)/;
  const m2 = cleaned.match(untilRegex);
  if (m2) return `${m2[1]}-${m2[2].padStart(2, '0')}-${m2[3].padStart(2, '0')}`;

  return null;
}

/**
 * 페이지 전체 텍스트에서 등급 키워드 자동 추출.
 * 광주/전남 협회 공고문 패턴: "신입부", "5부", "4부"... "오픈" 등.
 *
 * 정밀하지 않으니 사이트별 파서에서 override 권장.
 */
export function extractTennisGradesFromText(text: string): string[] {
  const found: Set<string> = new Set();
  if (/신입|노부|새내기|초보/i.test(text)) found.add('rookie');
  if (/\b5\s*부\b|5부|디비전5|d5/i.test(text)) found.add('div5');
  if (/\b4\s*부\b|4부|디비전4|d4/i.test(text)) found.add('div4');
  if (/\b3\s*부\b|3부|디비전3|d3/i.test(text)) found.add('div3');
  if (/\b2\s*부\b|2부|디비전2|d2/i.test(text)) found.add('div2');
  if (/\b1\s*부\b|1부|디비전1|d1|오픈/i.test(text)) found.add('div1');
  // 모든 부수 대회면 전체
  if (found.size === 0 && /(전\s*부수|모든\s*부수)/i.test(text)) {
    return ['rookie', 'div5', 'div4', 'div3', 'div2', 'div1'];
  }
  return [...found];
}
