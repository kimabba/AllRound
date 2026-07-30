// _shared/crawler/divisions.ts
// tennis_divisions 사전을 단일 진실로 삼는 범용 부서 해석기.
// 협회별 하드코딩 KEYWORD_MAP을 대체(블로커 #3).

import type { SupabaseClient } from '@supabase/supabase-js';

export interface DivisionDictRow {
  code: string;
  synonyms: string[];
  label_ko: string;
}

/**
 * 대회 텍스트에서 부서 코드 추출. dict의 각 행에 대해 synonym 중 하나라도
 * text에 substring으로 존재하면 그 code를 채택(dict 순서 유지).
 * 하나도 안 맞으면 unmapped=true, codes=[] (기본값 추측 안 함 — draft 검수에서 보정).
 */
export function mapDivisionsByDict(
  text: string,
  dict: DivisionDictRow[],
): { codes: string[]; label: string; unmapped: boolean } {
  const codes: string[] = [];
  const labels: string[] = [];
  for (const row of dict) {
    if (row.synonyms.some((kw) => text.includes(kw))) {
      codes.push(row.code);
      labels.push(row.label_ko);
    }
  }
  return { codes, label: labels.join(' · '), unmapped: codes.length === 0 };
}

/**
 * 크롤 시점에 org의 활성 부서 사전 로드. crawl당 1회 호출 권장.
 *
 * 시니어(kstf)는 org 를 가리지 않고 함께 싣는다. 연령 부서는 전국 공통이라 시도협회
 * 대회에도 그대로 나온다 — 광주 서구 어르신 대회의 '어르신60+/65+/70+' 가 그 예다.
 * org 만으로 좁히면 그 부서가 영원히 미매칭으로 남는다. synonyms 가 연령 표기라
 * 다른 부서명과 겹칠 여지도 낮다.
 */
export async function loadDivisionDict(
  supabase: SupabaseClient,
  orgCode: string,
): Promise<DivisionDictRow[]> {
  const orgCodes = orgCode === 'kstf' ? [orgCode] : [orgCode, 'kstf'];
  const { data, error } = await supabase
    .from('tennis_divisions')
    .select('code, synonyms, label_ko')
    .in('org_code', orgCodes)
    .eq('is_active', true)
    .order('code');
  if (error) throw new Error(`loadDivisionDict(${orgCode}) 실패: ${error.message}`);
  return (data ?? []) as DivisionDictRow[];
}
