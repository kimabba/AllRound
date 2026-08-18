-- my_schedule_conflicts 버그 수정: 대회-대회 겹침의 conflict_date 를 "겹침이
-- 시작되는 날"(overlap_start)로만 계산해서, 겹침이 요청 기간보다 먼저 시작해
-- 계속 이어지는 경우까지 통째로 걸러졌다.
--
-- 예: 대회 A(20~35일) · B(25~40일) → 실제 겹침은 25~35일. p_date_from=33일로
-- 조회하면(예: "다음주") 33~35일에 여전히 겹치는데, conflict_date(=25)가 33보다
-- 이르다는 이유로 결과에서 빠져 "겹침 없어요"로 오답했다.
--
-- 수정: 겹침 구간을 [conflict_date, conflict_end] 로 온전히 계산하고, 요청
-- 기간과 "구간이 겹치는지"(conflict_date <= p_date_to and conflict_end >=
-- p_date_from)로 판정한다. 대회-모임 겹침은 원래 하루짜리라
-- conflict_date=conflict_end 로 두면 기존 동작과 동일하다.

begin;

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
      greatest(t1.start_date, t2.start_date) as conflict_date,
      -- 겹침이 실제로 끝나는 날. 두 대회 중 먼저 끝나는 쪽이 겹침의 끝이다.
      least(coalesce(t1.end_date, t1.start_date), coalesce(t2.end_date, t2.start_date))
        as conflict_end
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
      (e.starts_at at time zone 'Asia/Seoul')::date as conflict_date,
      -- 모임은 하루짜리 — 시작=끝.
      (e.starts_at at time zone 'Asia/Seoul')::date as conflict_end
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
  -- p_date_to 없으면 기존과 동일한 오늘+90일 상한. p_date_from 없으면 하한 없음(기존
  -- 동작 — 실제로는 위 "아직 안 끝난 대회만" 필터로 conflict_end 가 항상 오늘 이후라
  -- 손해가 없다). p_date_from 있을 땐 구간(conflict_date~conflict_end)이 요청
  -- 기간과 겹치는지로 판정 — 시작일만 보면 이 마이그레이션이 고치는 버그가 재발한다.
  where conflict_date <= coalesce(p_date_to, (now() at time zone 'Asia/Seoul')::date + 90)
    and (p_date_from is null or conflict_end >= p_date_from)
  order by conflict_date, kind, a_id, b_id
  limit 10
$$;

comment on function public.my_schedule_conflicts is
  '호출자가 즐겨찾기한 대회끼리, 그리고 그 대회 기간과 본인이 속한 클럽 모임이 겹치는지 반환. p_date_from/p_date_to 없으면 오늘~90일. 겹침 구간 전체를 요청 기간과 비교(시작일만 보지 않음). 챗봇 match_schedule 라우팅 전용.';

commit;
