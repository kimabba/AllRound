// 크롤 후 대회 노출 상태(published ↔ closed) 동기화.
//
// auto-close 는 원래 crawl-dispatch 안에 인라인으로 있었고 단방향이었다(JY-151):
// 파서가 한때 잘못 뽑은 과거 날짜에 걸려 closed 가 된 대회는, 재크롤이 start_date 를
// 고쳐도 status 는 그대로라 마감 전인데 홈·캘린더에서 빠진 채 굳었다. 여기서 양방향으로
// 맞춘다.
//
// 되살리기가 안전한 근거: tournaments.status='closed' 는 이 함수(=크롤 dispatcher)만
// 만든다. 관리자 화면의 상태 드롭다운은 draft/published/rejected 뿐이고
// (scripts/harness/check_static_rules.py 가 고정), 반려는 'rejected' 라는 별도 값이다.
// 실제로 끝난 대회는 start_date 가 과거라 되살리기 조건에 걸리지 않는다.

import type { SupabaseClient } from '@supabase/supabase-js';

export interface StatusSyncResult {
  closed: number;
  reopened: number;
}

/**
 * @param todayKst 'YYYY-MM-DD' (KST 기준 오늘). start_date 는 date 컬럼이라 KST 로 비교한다.
 */
export async function syncTournamentStatus(
  supabase: SupabaseClient,
  todayKst: string,
): Promise<StatusSyncResult> {
  // start_date 가 지난 published → closed
  const { count: closed } = await supabase
    .from('tournaments')
    .update({ status: 'closed' }, { count: 'exact' })
    .eq('status', 'published')
    .lt('start_date', todayKst);

  // start_date 가 다시 미래가 된 closed → published (날짜 교정 반영)
  const { count: reopened } = await supabase
    .from('tournaments')
    .update({ status: 'published' }, { count: 'exact' })
    .eq('status', 'closed')
    .gte('start_date', todayKst);

  return { closed: closed ?? 0, reopened: reopened ?? 0 };
}
