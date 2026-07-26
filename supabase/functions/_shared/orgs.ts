import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * 협회 코드가 DB(tennis_orgs)에 있고 활성인지 확인한다.
 * 정적 목록(TENNIS_ORGS)으로 검증하면 협회를 DB 에 추가해도 제보/검색이 거절된다(JY-135, #330).
 * submit(쓰기)과 search(읽기) 둘 다 여기서 검증한다 — 같은 로직 두 벌 두지 않는다.
 *
 * status 를 함께 반환하는 이유: DB 조회 자체 실패(장애)와 협회 미존재(입력 오류)는
 * 원인이 다르다. grade 카탈로그 검증(#319)과 맞춰 전자는 503, 후자는 400 으로 구분한다.
 */
export async function assertKnownOrgs(
  client: SupabaseClient,
  orgs: string[],
): Promise<{ message: string; status: number } | null> {
  if (orgs.length === 0) return null;
  const { data, error } = await client
    .from('tennis_orgs')
    .select('code')
    .in('code', orgs)
    .eq('is_active', true);
  if (error) return { message: 'org 검증에 실패했습니다', status: 503 };
  const known = new Set((data ?? []).map((r: { code: string }) => r.code));
  const unknown = orgs.find((o) => !known.has(o));
  return unknown ? { message: `invalid org: ${unknown}`, status: 400 } : null;
}
