-- 087_club_event_fee_capacity.sql은 운영 히스토리 복원용이라 CLI 적용 대상이 아니다.
-- 정원 검증 RPC는 실제 적용되는 타임스탬프 마이그레이션으로 분리한다.

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
begin
  if p_status not in ('going', 'not_going') then
    raise exception 'invalid attendance status';
  end if;

  if not public.is_event_club_member(p_event_id) then
    raise exception 'club membership required';
  end if;

  select capacity
  into v_capacity
  from public.club_events
  where id = p_event_id
  for update;

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
    event_id,
    user_id,
    status,
    responded_at
  )
  values (p_event_id, auth.uid(), p_status, now())
  on conflict (event_id, user_id) do update
    set status = excluded.status,
        responded_at = excluded.responded_at;
end;
$$;

revoke all on function public.respond_club_event(uuid, text) from public;
grant execute on function public.respond_club_event(uuid, text) to authenticated;

notify pgrst, 'reload schema';
