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
  -- conflict_date = "겹침이 실제로 일어나는 날". 정렬·90일 지평선 판정은 전부 이 값으로
  -- 한다 — self-join 의 t1/t2 는 UUID 크기로 갈리므로 한쪽 start_date 를 기준 삼으면
  -- 같은 데이터도 UUID 에 따라 결과가 달라진다. 날짜의 "오늘"은 세션 타임존이 아니라
  -- KST 로 고정한다.
  select kind, a_id, a_title, a_start, a_end, b_id, b_title, b_date from (
    -- 즐겨찾기한 대회끼리 날짜 겹침. f2.tournament_id > f1.tournament_id 로 (A,B)/(B,A)
    -- 중복과 자기 자신(A,A)을 함께 제거한다.
    select
      'tournament_vs_tournament'::text as kind,
      t1.id as a_id, t1.title as a_title, t1.start_date as a_start, t1.end_date as a_end,
      t2.id as b_id, t2.title as b_title, t2.start_date as b_date,
      -- 두 대회 중 늦게 시작하는 날 = 겹침이 시작되는 날.
      greatest(t1.start_date, t2.start_date) as conflict_date
    from public.tournament_favorites f1
    join public.tournaments t1 on t1.id = f1.tournament_id
    join public.tournament_favorites f2
      on f2.user_id = f1.user_id and f2.tournament_id > f1.tournament_id
    join public.tournaments t2 on t2.id = f2.tournament_id
    where f1.user_id = (select auth.uid())
      -- 본인 제보 draft/rejected 는 RLS 로는 보이지만 확정된 대회가 아니다 —
      -- chat/index.ts 의 대회 노출 기준과 동일하게 published/closed 만.
      and t1.status in ('published', 'closed')
      and t2.status in ('published', 'closed')
      and t1.start_date <= coalesce(t2.end_date, t2.start_date)
      and t2.start_date <= coalesce(t1.end_date, t1.start_date)
      -- 둘 다 아직 안 끝난 대회만(진행 중 포함).
      and coalesce(t1.end_date, t1.start_date) >= (now() at time zone 'Asia/Seoul')::date
      and coalesce(t2.end_date, t2.start_date) >= (now() at time zone 'Asia/Seoul')::date

    union all

    -- 즐겨찾기한 대회 기간 중 내 클럽(active 멤버) 모임이 있는 경우.
    -- starts_at 은 timestamptz 라 그냥 ::date 하면 UTC 기준으로 잘려 한국 새벽/아침
    -- 모임이 하루 앞 날짜가 된다. KST 로 변환한 뒤 날짜를 뽑는다.
    select
      'tournament_vs_club_event'::text as kind,
      t.id as a_id, t.title as a_title, t.start_date as a_start, t.end_date as a_end,
      e.id as b_id, e.title as b_title, (e.starts_at at time zone 'Asia/Seoul')::date as b_date,
      -- 겹침이 일어나는 날 = 모임 당일(KST).
      (e.starts_at at time zone 'Asia/Seoul')::date as conflict_date
    from public.tournament_favorites f
    join public.tournaments t on t.id = f.tournament_id
    join public.club_members m on m.user_id = f.user_id and m.status = 'active'
    join public.club_events e on e.club_id = m.club_id
    where f.user_id = (select auth.uid())
      and t.status in ('published', 'closed')
      and (e.starts_at at time zone 'Asia/Seoul')::date
        between t.start_date and coalesce(t.end_date, t.start_date)
      -- 이미 시작했지만 안 끝난 대회도 포함(start_date >= 오늘 이면 빠진다).
      and coalesce(t.end_date, t.start_date) >= (now() at time zone 'Asia/Seoul')::date
  ) conflicts
  -- 지평선 판정도 conflict_date 로 — least()/한쪽 start_date 기준이면 겹침 자체는
  -- 90일 밖인데 이른 쪽 대회가 90일 안이라는 이유로 통과해 LIMIT 10 을 잠식한다.
  where conflict_date <= (now() at time zone 'Asia/Seoul')::date + p_horizon_days
  order by conflict_date, kind, a_id, b_id
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
