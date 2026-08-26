import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * 지역 코드 정본은 DB(regions)다 — 협회(tennis_orgs, JY-135/#330)와 같은 원칙.
 * 정적 목록(REGION_CODES)으로 검증하면 지역을 DB 에 추가해도 제보/검색이 거절된다(P7).
 * deprecated 묶음 코드(seoul_metro 등)는 is_active=false 라 여기서도 거절된다 —
 * 정적 REGION_CODES 도 묶음 코드를 제외하고 있었으므로 기존 동작과 같다.
 *
 * status 를 함께 반환하는 이유: DB 조회 자체 실패(장애)와 지역 미존재(입력 오류)는
 * 원인이 다르다. orgs.ts(#330)와 맞춰 전자는 503, 후자는 400 으로 구분한다.
 */
export async function fetchActiveRegionCodes(
  client: SupabaseClient,
): Promise<{ codes: Set<string> } | { message: string; status: number }> {
  const { data, error } = await client
    .from('regions')
    .select('code')
    .eq('is_active', true);
  if (error) return { message: 'region 카탈로그 조회에 실패했습니다', status: 503 };
  return { codes: new Set((data ?? []).map((r: { code: string }) => r.code)) };
}

/**
 * fetchActiveRegionCodes 로 읽은 활성 집합(요청당 조회 1회)에 대해 코드들을 검증한다.
 * submit(쓰기)과 search(읽기) 둘 다 여기서 검증한다 — 같은 로직 두 벌 두지 않는다.
 */
export function assertKnownRegions(
  codes: string[],
  active: ReadonlySet<string>,
): { message: string; status: number } | null {
  const unknown = codes.find((c) => !active.has(c));
  return unknown ? { message: `invalid region_code: ${unknown}`, status: 400 } : null;
}
