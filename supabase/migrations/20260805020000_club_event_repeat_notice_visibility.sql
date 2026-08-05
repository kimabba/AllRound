-- 모임 일정 반복 표시, 조기 종료 참석 차단, 공지의 게시판별 동시 노출.

begin;

alter table public.club_events
  add column if not exists repeat_interval text
  check (repeat_interval is null or repeat_interval in ('weekly', 'monthly'));

alter table public.club_posts
  add column if not exists notice_visible_tags text[] not null default '{}';

alter table public.club_posts
  drop constraint if exists club_posts_notice_visible_tags_check;
alter table public.club_posts
  add constraint club_posts_notice_visible_tags_check check (
    notice_visible_tags <@ array['free', 'recruit', 'photo', 'intro']::text[]
    and (tag = 'notice' or cardinality(notice_visible_tags) = 0)
  );

create or replace function public.respond_club_event(
  p_event_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity integer;
  v_going integer;
  v_current text;
  v_ended_early_at timestamptz;
begin
  if p_status not in ('going', 'not_going') then
    raise exception 'invalid attendance status';
  end if;

  if not public.is_event_club_member(p_event_id) then
    raise exception 'club membership required';
  end if;

  select capacity, ended_early_at
  into v_capacity, v_ended_early_at
  from public.club_events
  where id = p_event_id
  for update;

  if v_ended_early_at is not null then
    raise exception 'event ended early';
  end if;

  select status
  into v_current
  from public.club_event_attendees
  where event_id = p_event_id
    and user_id = auth.uid();

  if p_status = 'going'
    and v_current is distinct from 'going'
    and v_capacity is not null
  then
    select count(*)
    into v_going
    from public.club_event_attendees
    where event_id = p_event_id
      and status = 'going';

    if v_going >= v_capacity then
      raise exception 'event capacity reached';
    end if;
  end if;

  insert into public.club_event_attendees (
    event_id, user_id, status, responded_at
  ) values (
    p_event_id, auth.uid(), p_status, now()
  )
  on conflict (event_id, user_id) do update
    set status = excluded.status,
        responded_at = excluded.responded_at;
end;
$$;

revoke all on function public.respond_club_event(uuid, text) from public;
grant execute on function public.respond_club_event(uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;
