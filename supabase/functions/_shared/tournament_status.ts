// 크롤 후 대회 노출 상태(published ↔ closed) 동기화.
//
// auto-close 는 원래 crawl-dispatch 안에 인라인으로 있었고 단방향이었다(JY-151):
// 파서가 한때 잘못 뽑은 과거 날짜에 걸려 closed 가 된 대회는, 재크롤이 start_date 를
// 고쳐도 status 는 그대로라 마감 전인데 홈·캘린더에서 빠진 채 굳었다. 여기서 양방향으로
// 맞춘다.
//
// 되살리기가 안전한 근거: 앱에서 tournaments.status='closed' 를 만드는 경로는 이 함수뿐이다.
// 관리자 화면의 상태 드롭다운은 draft/published/rejected 뿐이고
// (scripts/harness/check_static_rules.py 가 고정), 반려는 'rejected' 라는 별도 값이며,
// 027 의 close_expired_tournaments() RPC·cron 은 프로덕션에 존재하지 않는다.
// 실제로 끝난 대회는 start_date 가 과거라 되살리기 조건에 걸리지 않는다.
//
// 남은 구멍 두 개(둘 다 현재 데이터에서는 손해가 없어 이번엔 그대로 둔다):
//   1) RLS tournaments_admin_all 은 관리자에게 전체 update 를 허용한다. Studio 로 직접
//      닫은 대회는 미래 날짜면 여기서 되살아난다. 수동 마감을 도입하려면 auto/수동
//      구분 컬럼이 먼저다.
//   2) 마감·되살리기 모두 start_date 만 본다. 진행 중인 다일 대회(start 과거·end 미래)는
//      마감되고 되살아나지도 않는다. 다만 "시작일은 지났는데 접수는 열려 있는" 대회는
//      실제로 0건이라(접수 마감이 늘 시작일보다 앞선다) 신청 기회를 잃는 경우가 없다.

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
