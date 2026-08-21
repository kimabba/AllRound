// 크롤 후 대회 노출 상태(published ↔ closed) 동기화.
//
// auto-close 는 원래 crawl-dispatch 안에 인라인으로 있었고 단방향이었다(JY-151):
// 파서가 한때 잘못 뽑은 과거 날짜에 걸려 closed 가 된 대회는, 재크롤이 start_date 를
// 고쳐도 status 는 그대로라 마감 전인데 홈·캘린더에서 빠진 채 굳었다. 여기서 양방향으로
// 맞춘다.
//
// status='closed' 는 두 "이유"로 만들어진다 — 날짜가 지났거나(delisted_at NULL),
// 목록에서 이탈했거나(delisted_at NOT NULL, 아래 closeDelistedTournaments). 되살리기는
// 날짜-close 만 되돌린다(delisted_at is null 가드) — 안 그러면 목록이탈로 닫은 대회를
// start_date 가 아직 미래라는 이유만으로 매 run 마다 되살려 기능이 무효화된다.
//
// 되살리기가 안전한 근거: 앱에서 tournaments.status='closed' 를 만드는 경로는 이 모듈뿐이다.
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
  delisted: number;
}

const DELIST_AFTER_DAYS = 7;

/**
 * 크롤 소스 목록에서 DELIST_AFTER_DAYS 일 넘게 안 보인 published 대회를 닫는다.
 *
 * "안 보였다"의 판정은 last_seen_at < cutoff **그리고** last_seen_at <
 * last_listing_parsed_at(그 소스가 실제로 last_seen_at 이후 다시 전체 목록을 훑은
 * 적이 있음) 둘 다 필요하다 — 사이트가 며칠 조용하거나(no_change), 셀렉터가 깨져
 * 빈 목록이 오거나, source 가 잠깐 비활성화된 경우 전부 last_listing_parsed_at 이
 * last_seen_at 을 못 앞지르므로 조건 불충족 → 오폐쇄가 없다. source ≤10개 수준이라
 * 소스별 루프로 처리한다(별도 SQL 함수/cron 은 만들지 않는다 — 027 이 "환경마다
 * 존재가 달라질 수 있는 SQL 객체"로 사고났던 교훈).
 */
async function closeDelistedTournaments(supabase: SupabaseClient): Promise<number> {
  const { data: sources } = await supabase
    .from('crawl_sources')
    .select('slug, last_listing_parsed_at')
    .not('last_listing_parsed_at', 'is', null);
  if (!sources || sources.length === 0) return 0;

  const cutoff = new Date(Date.now() - DELIST_AFTER_DAYS * 86_400_000).toISOString();
  const now = new Date().toISOString();
  let delisted = 0;
  for (const s of sources as Array<{ slug: string; last_listing_parsed_at: string }>) {
    const { count } = await supabase
      .from('tournaments')
      .update({ status: 'closed', delisted_at: now }, { count: 'exact' })
      .eq('status', 'published')
      .eq('source', s.slug)
      .not('last_seen_at', 'is', null)
      .lt('last_seen_at', cutoff)
      .lt('last_seen_at', s.last_listing_parsed_at);
    delisted += count ?? 0;
  }
  return delisted;
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

  // start_date 가 다시 미래가 된 closed → published (날짜 교정 반영).
  // delisted_at is null: 목록이탈로 닫힌 대회는 날짜 교정으로 되살아나지 않는다 —
  // 재등장은 upsertTournament 가 담당한다.
  const { count: reopened } = await supabase
    .from('tournaments')
    .update({ status: 'published' }, { count: 'exact' })
    .eq('status', 'closed')
    .is('delisted_at', null)
    .gte('start_date', todayKst);

  const delisted = await closeDelistedTournaments(supabase);

  return { closed: closed ?? 0, reopened: reopened ?? 0, delisted };
}
