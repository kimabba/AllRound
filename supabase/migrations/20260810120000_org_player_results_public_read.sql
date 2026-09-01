-- 랭킹 표에서 아무 선수나 눌러 전적을 보는 기능 준비.
--
-- org_rankings 는 이미 로그인 사용자 전체에게 공개(org_rankings_read, auth.role() =
-- 'authenticated')다 — 랭킹 표 자체가 이름·소속·점수를 누구에게나 보여준다.
-- org_player_results 는 지금까지 "본인 연결(confirmed)된 선수"만 읽을 수 있었는데
-- (org_player_results_own_select, 20260804010000), 같은 협회 공표 데이터를 랭킹
-- 표는 공개하면서 전적만 막을 이유가 없다. org_rankings 와 같은 조건으로 연다.
--
-- 기존 정책(own_select, admin_all)은 그대로 둔다 — RLS 정책은 OR 로 합쳐지므로
-- 더 넓은 정책을 추가해도 안전하고, 의도(연결 확인/관리자 우회)를 남겨둘 값어치가
-- 있다.
--
-- 주의: 이 정책만으로는 화면에 새 기능이 뜨지 않는다. 크롤러(upsert_org_player_results)
-- 가 여전히 "연결 승인자 1명"만 적재하므로(20260804010000 주석), 비연결 선수는
-- 정책이 열려도 실제로 조회되는 행이 없다 — 데이터 자체를 늘리는 건 별도 작업이다.

begin;

create policy org_player_results_read on public.org_player_results
  for select to authenticated
  using (true);

commit;
