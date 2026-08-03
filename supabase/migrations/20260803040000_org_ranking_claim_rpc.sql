-- 랭킹 후보 조회
--
-- 무언(silent) 자동 매칭을 하지 않는 이유: 협회 개인 페이지가 전체 공개라
--   "본인만 아는 정보"로 검증할 수단이 없고, 오매칭 결과가 실명 자동 공개라
--   오류 비용이 비대칭적으로 크다. 후보만 제시하고 확정은 본인 원탭 + 관리자 승인.
--
-- 협회 데이터에 생년월일이 없어(개인 성적검색 입력이 이름 하나뿐) 매칭 요소는
--   이름 + 소속 협회 + 등록 부서 셋뿐이다.

begin;

create or replace function public.my_ranking_candidates()
returns table (
  org_code      text,
  division_code text,
  rank          int,
  player_name   text,
  org_player_id text,
  club_raw      text,
  rank_points   int,
  total_points  int
)
language sql
stable
security invoker
set search_path = public
as $$
  select r.org_code, r.division_code, r.rank, r.player_name,
         r.org_player_id, r.club_raw, r.rank_points, r.total_points
  from public.org_rankings r
  join public.users u
    on u.id = (select auth.uid())
  -- division_codes 는 users 가 아니라 user_tennis_orgs 에 있다.
  -- PK 가 (user_id, org, division) 이라 유저 1명이 협회별로 여러 행을 갖는다 —
  -- 조인이 협회 일치 조건(uto.org = r.org_code)을 자연히 만들어 준다.
  join public.user_tennis_orgs uto
    on uto.user_id = u.id
   and uto.org = r.org_code
   and r.division_code = any(uto.division_codes)
  where r.player_name = u.name
    and r.org_player_id is not null
    -- 이미 누군가와 연결 확정된 선수는 후보에서 제외
    and not exists (
      select 1 from public.org_player_links l
      where l.org_code = r.org_code
        and l.org_player_id = r.org_player_id
        and l.status = 'confirmed'
    )
    -- 내가 이미 신청한 것도 제외
    and not exists (
      select 1 from public.org_player_links l
      where l.org_code = r.org_code
        and l.org_player_id = r.org_player_id
        and l.user_id = (select auth.uid())
    );
$$;

comment on function public.my_ranking_candidates is
  '내 이름·소속 협회·등록 부서가 모두 일치하는 협회 랭킹 행을 후보로 제시한다. security invoker 라 org_rankings RLS 를 그대로 통과한다(로그인 필수).';

grant execute on function public.my_ranking_candidates to authenticated;

commit;
