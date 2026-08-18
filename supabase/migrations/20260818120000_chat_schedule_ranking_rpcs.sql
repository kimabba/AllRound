-- 챗봇 확장 — 일정 겹침 확인 / 랭킹 조회 RPC
--
-- 설계: docs/superpowers/specs/2026-08-18-chat-tournament-schedule-ranking-design.md
--
-- 둘 다 my_ranking_candidates(20260803040000) 패턴을 따른다: 인자로 user_id 를 받지
-- 않고 (select auth.uid()) 로 호출자 본인만 조회한다 — RLS 와 별개로 함수 자체가
-- 다른 사용자 데이터를 반환하지 않음을 보장한다. 앱은 랭킹을 계산하지 않고
-- org_rankings 미러 값을 그대로 옮긴다(테이블 코멘트 참고).

begin;

-- ═══════════════════════════════════════════════
-- my_schedule_conflicts — 즐겨찾기 대회끼리, 그리고 즐겨찾기 대회와
--   내가 속한 클럽의 모임 일정이 겹치는지 확인한다.
-- ═══════════════════════════════════════════════
create or replace function public.my_schedule_conflicts(p_horizon_days int default 90)
returns table (
  kind    text,
  a_id    uuid,
  a_title text,
  a_start date,
  a_end   date,
  b_id    uuid,
  b_title text,
  b_date  date
)
language sql
stable
security invoker
set search_path = public
as $$
  select * from (
    -- 즐겨찾기한 대회끼리 날짜 겹침. f2.tournament_id > f1.tournament_id 로 (A,B)/(B,A)
    -- 중복과 자기 자신(A,A)을 함께 제거한다.
    select
      'tournament_vs_tournament'::text as kind,
      t1.id as a_id, t1.title as a_title, t1.start_date as a_start, t1.end_date as a_end,
      t2.id as b_id, t2.title as b_title, t2.start_date as b_date
    from public.tournament_favorites f1
    join public.tournaments t1 on t1.id = f1.tournament_id
    join public.tournament_favorites f2
      on f2.user_id = f1.user_id and f2.tournament_id > f1.tournament_id
    join public.tournaments t2 on t2.id = f2.tournament_id
    where f1.user_id = (select auth.uid())
      and t1.start_date <= coalesce(t2.end_date, t2.start_date)
      and t2.start_date <= coalesce(t1.end_date, t1.start_date)
      -- t1/t2 는 UUID 크기로 갈리므로 날짜 조건을 t1 한쪽에만 걸면 안 된다(같은 데이터도
      -- UUID 가 뒤바뀌면 결과가 달라짐). "둘 다 아직 안 끝났고, 한쪽이라도 기간 안에 시작"으로 건다.
      and coalesce(t1.end_date, t1.start_date) >= current_date
      and coalesce(t2.end_date, t2.start_date) >= current_date
      and least(t1.start_date, t2.start_date) <= current_date + p_horizon_days

    union all

    -- 즐겨찾기한 대회 기간 중 내 클럽(active 멤버) 모임이 있는 경우.
    -- starts_at 은 timestamptz 라 그냥 ::date 하면 UTC 기준으로 잘려 한국 새벽/아침
    -- 모임이 하루 앞 날짜가 된다. KST 로 변환한 뒤 날짜를 뽑는다.
    select
      'tournament_vs_club_event'::text as kind,
      t.id as a_id, t.title as a_title, t.start_date as a_start, t.end_date as a_end,
      e.id as b_id, e.title as b_title, (e.starts_at at time zone 'Asia/Seoul')::date as b_date
    from public.tournament_favorites f
    join public.tournaments t on t.id = f.tournament_id
    join public.club_members m on m.user_id = f.user_id and m.status = 'active'
    join public.club_events e on e.club_id = m.club_id
    where f.user_id = (select auth.uid())
      and (e.starts_at at time zone 'Asia/Seoul')::date
        between t.start_date and coalesce(t.end_date, t.start_date)
      -- 이미 시작했지만 안 끝난 대회도 포함(start_date >= current_date 면 빠진다).
      and coalesce(t.end_date, t.start_date) >= current_date
      and t.start_date <= current_date + p_horizon_days
  ) conflicts
  order by a_start, kind, a_id, b_id
  limit 10
$$;

comment on function public.my_schedule_conflicts is
  '호출자가 즐겨찾기한 대회끼리, 그리고 그 대회 기간과 본인이 속한 클럽 모임이 겹치는지 반환. 챗봇 match_schedule 라우팅 전용.';

revoke execute on function public.my_schedule_conflicts(int) from public, anon;
grant execute on function public.my_schedule_conflicts(int) to authenticated, service_role;

-- ═══════════════════════════════════════════════
-- my_confirmed_ranking — 본인 인증 연결(confirmed)된 협회 랭킹만 반환.
-- ═══════════════════════════════════════════════
create or replace function public.my_confirmed_ranking()
returns table (
  org_code      text,
  division_code text,
  org_player_id text,
  rank          int,
  rank_points   int,
  total_points  int,
  fetched_at    timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select r.org_code, r.division_code, l.org_player_id, r.rank, r.rank_points, r.total_points, r.fetched_at
  from public.org_player_links l
  join public.org_rankings r
    on r.org_code = l.org_code and r.org_player_id = l.org_player_id
  where l.user_id = (select auth.uid())
    and l.status = 'confirmed'
$$;

comment on function public.my_confirmed_ranking is
  '호출자의 본인 인증 연결(confirmed)된 협회 랭킹만 반환. 연결 없으면 0행. 챗봇 my_profile 라우팅 전용.';

revoke execute on function public.my_confirmed_ranking() from public, anon;
grant execute on function public.my_confirmed_ranking() to authenticated, service_role;

commit;
