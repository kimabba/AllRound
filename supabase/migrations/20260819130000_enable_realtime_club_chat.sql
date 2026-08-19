-- 클럽 채팅을 실시간으로 전달하고 과도한 연속 전송을 제한한다.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'club_chat_messages'
  ) then
    alter publication supabase_realtime
      add table public.club_chat_messages;
  end if;
end;
$$;

create index if not exists club_chat_messages_sender_created_idx
  on public.club_chat_messages (sender_id, created_at desc);

create or replace function public.enforce_club_chat_message_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (
    select count(*)
    from public.club_chat_messages message
    where message.sender_id = new.sender_id
      and message.created_at >= now() - interval '1 minute'
  ) >= 20 then
    raise exception 'club chat message rate limit exceeded'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger club_chat_messages_rate_limit
  before insert on public.club_chat_messages
  for each row execute function public.enforce_club_chat_message_rate_limit();

revoke all on function public.enforce_club_chat_message_rate_limit()
  from public, anon, authenticated;
grant execute on function public.enforce_club_chat_message_rate_limit()
  to service_role;

commit;
