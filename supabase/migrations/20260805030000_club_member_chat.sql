-- 같은 모임의 활성 멤버만 사용하는 1:1·단체 채팅.

begin;

create table public.club_chat_threads (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  kind text not null check (kind in ('direct', 'group')),
  direct_key text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint club_chat_threads_kind_key_check check (
    (kind = 'group' and direct_key is null)
    or (kind = 'direct' and direct_key is not null)
  )
);

create unique index club_chat_threads_one_group_idx
  on public.club_chat_threads (club_id) where kind = 'group';
create unique index club_chat_threads_direct_key_idx
  on public.club_chat_threads (club_id, direct_key) where kind = 'direct';
create index club_chat_threads_recent_idx
  on public.club_chat_threads (club_id, last_message_at desc);

create table public.club_chat_participants (
  thread_id uuid not null references public.club_chat_threads(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

create index club_chat_participants_user_idx
  on public.club_chat_participants (user_id, thread_id);

create table public.club_chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.club_chat_threads(id) on delete cascade,
  sender_id uuid references public.users(id) on delete set null,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index club_chat_messages_thread_created_idx
  on public.club_chat_messages (thread_id, created_at);

alter table public.club_chat_threads enable row level security;
alter table public.club_chat_participants enable row level security;
alter table public.club_chat_messages enable row level security;

create or replace function public.can_access_club_chat(p_thread_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.club_chat_threads thread
    join public.club_members member
      on member.club_id = thread.club_id
     and member.user_id = (select auth.uid())
     and member.status = 'active'
    where thread.id = p_thread_id
      and (
        thread.kind = 'group'
        or (
          exists (
            select 1 from public.club_chat_participants participant
            where participant.thread_id = thread.id
              and participant.user_id = (select auth.uid())
          )
          and not exists (
            select 1 from public.club_chat_participants other_participant
            where other_participant.thread_id = thread.id
              and other_participant.user_id <> (select auth.uid())
              and public.is_user_blocked_pair(other_participant.user_id)
          )
        )
      )
  );
$$;

create policy club_chat_threads_read on public.club_chat_threads
  for select to authenticated
  using (public.can_access_club_chat(id));

create policy club_chat_participants_read on public.club_chat_participants
  for select to authenticated
  using (public.can_access_club_chat(thread_id));

create policy club_chat_messages_read on public.club_chat_messages
  for select to authenticated
  using (
    public.can_access_club_chat(thread_id)
    and (sender_id is null or not public.is_user_blocked_pair(sender_id))
  );

create policy club_chat_messages_insert on public.club_chat_messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select public.has_accepted_current_ugc_terms())
    and not (select public.has_active_ugc_penalty(
      array['community_restriction']::public.ugc_penalty_type[]
    ))
    and public.can_access_club_chat(thread_id)
  );

create or replace function public.open_club_chat(
  p_club_id uuid,
  p_other_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_thread_id uuid;
  v_direct_key text;
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;
  if not public.is_active_club_member(p_club_id) then
    raise exception 'club membership required';
  end if;

  if p_other_user_id is null then
    insert into public.club_chat_threads (club_id, kind, created_by)
    values (p_club_id, 'group', v_user_id)
    on conflict (club_id) where kind = 'group' do update
      set club_id = excluded.club_id
    returning id into v_thread_id;
  else
    if p_other_user_id = v_user_id then
      raise exception 'cannot chat with yourself';
    end if;
    if public.is_user_blocked_pair(p_other_user_id) then
      raise exception 'blocked user chat is not available';
    end if;
    if not exists (
      select 1 from public.club_members
      where club_id = p_club_id
        and user_id = p_other_user_id
        and status = 'active'
    ) then
      raise exception 'other user is not an active member';
    end if;
    v_direct_key := least(v_user_id::text, p_other_user_id::text)
      || ':' || greatest(v_user_id::text, p_other_user_id::text);
    insert into public.club_chat_threads (
      club_id, kind, direct_key, created_by
    ) values (
      p_club_id, 'direct', v_direct_key, v_user_id
    )
    on conflict (club_id, direct_key) where kind = 'direct' do update
      set direct_key = excluded.direct_key
    returning id into v_thread_id;

    insert into public.club_chat_participants (thread_id, user_id)
    values (v_thread_id, v_user_id), (v_thread_id, p_other_user_id)
    on conflict do nothing;
  end if;

  return v_thread_id;
end;
$$;

create or replace function public.touch_club_chat_thread()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.club_chat_threads
  set last_message_at = new.created_at
  where id = new.thread_id;
  return new;
end;
$$;

create trigger club_chat_messages_touch_thread
  after insert on public.club_chat_messages
  for each row execute function public.touch_club_chat_thread();

alter table public.notifications
  drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check check (type in (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request', 'club_inquiry_received', 'club_inquiry_reply',
    'club_dues_reminder', 'club_chat_message'
  ));

create or replace function public.notify_club_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_thread public.club_chat_threads%rowtype;
  v_recipient uuid;
begin
  select * into v_thread from public.club_chat_threads where id = new.thread_id;
  for v_recipient in
    select recipient.user_id
    from (
      select participant.user_id
      from public.club_chat_participants participant
      where v_thread.kind = 'direct'
        and participant.thread_id = new.thread_id
      union
      select member.user_id
      from public.club_members member
      where v_thread.kind = 'group'
        and member.club_id = v_thread.club_id
        and member.status = 'active'
    ) recipient
    where recipient.user_id <> new.sender_id
      and not exists (
        select 1 from public.user_blocks block
        where (block.blocker_id = new.sender_id and block.blocked_id = recipient.user_id)
           or (block.blocker_id = recipient.user_id and block.blocked_id = new.sender_id)
      )
  loop
    insert into public.notifications (
      user_id, type, title, body, reference_type, reference_id, club_id
    ) values (
      v_recipient,
      'club_chat_message',
      case when v_thread.kind = 'group' then '새 단체 채팅' else '새 1:1 채팅' end,
      '새 메시지가 도착했습니다.',
      'club_chat:' || new.thread_id::text,
      new.id,
      v_thread.club_id
    ) on conflict do nothing;
  end loop;
  return new;
end;
$$;

create trigger club_chat_messages_notify
  after insert on public.club_chat_messages
  for each row execute function public.notify_club_chat_message();

revoke all on public.club_chat_threads, public.club_chat_participants,
  public.club_chat_messages from anon, authenticated;
grant select on public.club_chat_threads, public.club_chat_participants
  to authenticated, service_role;
grant select on public.club_chat_messages to authenticated, service_role;
grant insert (thread_id, sender_id, body) on public.club_chat_messages
  to authenticated;
grant insert on public.club_chat_messages to service_role;
grant insert, update, delete on public.club_chat_threads,
  public.club_chat_participants to service_role;

revoke all on function public.can_access_club_chat(uuid) from public;
grant execute on function public.can_access_club_chat(uuid)
  to authenticated, service_role;
revoke all on function public.open_club_chat(uuid, uuid) from public;
grant execute on function public.open_club_chat(uuid, uuid)
  to authenticated, service_role;
revoke all on function public.touch_club_chat_thread() from public;
grant execute on function public.touch_club_chat_thread() to service_role;
revoke all on function public.notify_club_chat_message() from public;
grant execute on function public.notify_club_chat_message() to service_role;

notify pgrst, 'reload schema';

commit;
