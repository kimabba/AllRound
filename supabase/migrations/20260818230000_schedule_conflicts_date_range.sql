-- my_schedule_conflicts 를 "오늘부터 N일" 고정 지평선 대신, 절대 기간(from/to)을
-- 받을 수 있게 확장한다. 챗봇이 "다음주"/"이번 주말" 같은 표현을 이미 파싱해
-- {from, to} 로 갖고 있는데(intent.ts extractDateRange), 지금까지는 이 값을
-- RPC 에 넘기지 않고 항상 기본 90일 지평선만 썼다.
--
-- 인자를 안 주면 기존과 동일하게 동작한다(오늘 ~ 오늘+90일, 하한 없음) —
-- 028 테스트의 my_schedule_conflicts() 무인자 호출 기대값을 그대로 유지.

begin;

drop function if exists public.my_schedule_conflicts(int);

create or replace function public.my_schedule_conflicts(
  p_date_from date default null,
  p_date_to   date default null
)
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
  select kind, a_id, a_title, a_start, a_end, b_id, b_title, b_date from (
    select
      'tournament_vs_tournament'::text as kind,
      t1.id as a_id, t1.title as a_title, t1.start_date as a_start, t1.end_date as a_end,
      t2.id as b_id, t2.title as b_title, t2.start_date as b_date,
      greatest(t1.start_date, t2.start_date) as conflict_date
    from public.tournament_favorites f1
    join public.tournaments t1 on t1.id = f1.tournament_id
    join public.tournament_favorites f2
      on f2.user_id = f1.user_id and f2.tournament_id > f1.tournament_id
    join public.tournaments t2 on t2.id = f2.tournament_id
    where f1.user_id = (select auth.uid())
      and t1.status in ('published', 'closed')
      and t2.status in ('published', 'closed')
      and t1.start_date <= coalesce(t2.end_date, t2.start_date)
      and t2.start_date <= coalesce(t1.end_date, t1.start_date)
      and coalesce(t1.end_date, t1.start_date) >= (now() at time zone 'Asia/Seoul')::date
      and coalesce(t2.end_date, t2.start_date) >= (now() at time zone 'Asia/Seoul')::date

    union all

    select
      'tournament_vs_club_event'::text as kind,
      t.id as a_id, t.title as a_title, t.start_date as a_start, t.end_date as a_end,
      e.id as b_id, e.title as b_title, (e.starts_at at time zone 'Asia/Seoul')::date as b_date,
      (e.starts_at at time zone 'Asia/Seoul')::date as conflict_date
    from public.tournament_favorites f
    join public.tournaments t on t.id = f.tournament_id
    join public.club_members m on m.user_id = f.user_id and m.status = 'active'
    join public.club_events e on e.club_id = m.club_id
    where f.user_id = (select auth.uid())
      and t.status in ('published', 'closed')
      and (e.starts_at at time zone 'Asia/Seoul')::date
        between t.start_date and coalesce(t.end_date, t.start_date)
      and coalesce(t.end_date, t.start_date) >= (now() at time zone 'Asia/Seoul')::date
      and (e.starts_at at time zone 'Asia/Seoul')::date >= (now() at time zone 'Asia/Seoul')::date
  ) conflicts
  -- p_date_to 없으면 기존과 동일한 오늘+90일 상한. p_date_from 없으면 하한 없음(기존 동작).
  where conflict_date <= coalesce(p_date_to, (now() at time zone 'Asia/Seoul')::date + 90)
    and (p_date_from is null or conflict_date >= p_date_from)
  order by conflict_date, kind, a_id, b_id
  limit 10
$$;

comment on function public.my_schedule_conflicts is
  '호출자가 즐겨찾기한 대회끼리, 그리고 그 대회 기간과 본인이 속한 클럽 모임이 겹치는지 반환. p_date_from/p_date_to 없으면 오늘~90일. 챗봇 match_schedule 라우팅 전용.';

revoke execute on function public.my_schedule_conflicts(date, date) from public, anon;
grant execute on function public.my_schedule_conflicts(date, date) to authenticated, service_role;

commit;
