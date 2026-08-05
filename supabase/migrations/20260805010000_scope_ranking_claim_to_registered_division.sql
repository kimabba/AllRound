-- 랭킹 본인 연결(클레임) 신청 자격을 "내가 등록한 협회·부서"로 좁힌다.
--
-- 배경: 지금까지 신청 진입로는 my_ranking_candidates() 자동 매칭 하나뿐이었다.
-- 그 RPC 는 users.name 이 협회 표의 선수명과 완전히 같아야 후보를 내는데,
-- 실측(2026-08-05 프로덕션) 가입자 20명 중 이름이 일치하는 사람이 0명이라
-- 개인 기록장 진입이 0건이었다. 앱에 검색 + 행별 신청 동선을 열면서,
-- 자격 강제는 앱이 아니라 여기(RLS)에 둔다 — org_player_links 는 PostgREST
-- 직행 테이블이라 정책이 유일한 방어선이다.
--
-- 좁히는 변경이다. 기존 자동 매칭으로 뜬 후보는 정의상 등록 부서 안이므로
-- 그 경로는 영향받지 않는다.
--
-- 이미 다른 사람과 confirmed 된 선수의 중복 신청은 여기서 막지 않는다 —
-- 화면이 그 행의 버튼을 숨기고, 최종 판단은 관리자 승인 큐가 한다.

drop policy if exists org_player_links_claim on public.org_player_links;

create policy org_player_links_claim
  on public.org_player_links
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    -- 신청 대상 선수가 "내가 등록한 협회의, 내가 등록한 부서" 랭킹에 실제로
    -- 올라 있어야 한다. user_tennis_orgs 는 PK 가 (user_id, org, division) 이라
    -- 유저 1명이 협회별 여러 행을 갖는다.
    and exists (
      select 1
      from public.org_rankings r
      join public.user_tennis_orgs uto
        on uto.user_id = (select auth.uid())
       and uto.org = r.org_code
       and r.division_code = any(uto.division_codes)
      where r.org_code = org_player_links.org_code
        and r.org_player_id = org_player_links.org_player_id
    )
  );

comment on policy org_player_links_claim on public.org_player_links is
  '본인 연결 신청: 내 계정으로, pending 으로만, 내가 등록한 협회·부서 랭킹에 있는 선수에 한해.';
