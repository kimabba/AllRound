-- 랭킹 성장 기록(2단계) — 순위 스냅샷도 랭킹 표 수준으로 공개
--
-- org_rankings 는 이미 로그인 사용자 전체에 공개(org_rankings_read)이고,
-- 오늘 org_player_results 도 같은 조건으로 열었다(org_player_results_read,
-- 20260810120000). org_ranking_snapshots(순위 추이)만 아직 본인 연결자로
-- 막혀 있어 같은 수준으로 연다.
--
-- 기존 정책(own_select, admin_all)은 그대로 둔다 — RLS 는 OR 로 합쳐지므로
-- 더 넓은 정책을 추가해도 안전하다.

begin;

create policy org_ranking_snapshots_read on public.org_ranking_snapshots
  for select to authenticated
  using (true);

commit;
