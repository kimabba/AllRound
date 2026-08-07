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
-- (다른 사람끼리 같은 선수를 놓고 경합하는 pending 은 정상이다.)

-- 한 협회에서 이미 confirmed 인 사람의 추가 신청은 막는다.
-- org_player_links_confirmed_user_key(협회당 유저 1명 1선수, partial unique)가
-- 승인 시점에 23505 를 내므로, 막지 않으면 "승인할 수 없는 pending"이 관리자
-- 큐에 쌓인다. 정책 표현식 안에서 org_player_links 를 직접 참조하면 정책이
-- 자기 자신에 재귀 적용되므로 security definer 함수로 감싼다.
create or replace function public.has_confirmed_org_link(p_org_code text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.org_player_links
    where org_code = p_org_code
      and user_id = (select auth.uid())
      and status = 'confirmed'
  );
$$;

-- 새 함수는 프로덕션에서 anon 에게 EXECUTE 가 기본 부여된다(로컬과 다름) —
-- 명시로 회수한다.
-- service_role 은 PUBLIC 기본 실행권한에 기대고 있어, revoke 하면 함께 사라진다
-- (011_api_role_grants 가 이 회귀를 잡는다) — 명시로 다시 부여한다.
revoke all on function public.has_confirmed_org_link(text) from public, anon;
grant execute on function public.has_confirmed_org_link(text)
  to authenticated, service_role;

comment on function public.has_confirmed_org_link is
  '내가 이 협회에서 이미 확정 연결된 상태인가. org_player_links_claim 정책 전용 — 정책이 자기 테이블을 참조해 재귀하는 것을 피하려고 분리했다.';

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
        -- 이름이 같아야 한다(Commander 결정 2026-08-05). 실측상 한 협회 안에서
        -- 동명이인이 0건이라(3,540명 전원 유일) 이름 하나로 사람이 특정된다.
        -- 협회 표의 이름에는 공백·앞뒤 여백이 없어 그대로 비교한다.
        and r.player_name = (
          select u.name from public.users u where u.id = (select auth.uid())
        )
    )
    and not public.has_confirmed_org_link(org_code)
  );

comment on policy org_player_links_claim on public.org_player_links is
  '본인 연결 신청: 내 계정으로, pending 으로만, 내가 등록한 협회·부서 랭킹에 있고 내 이름과 같은 선수에 한해, 그 협회에 아직 확정 연결이 없을 때.';
