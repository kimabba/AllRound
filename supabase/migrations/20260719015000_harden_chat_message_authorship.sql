-- Only the verified chat Edge Function may persist conversation turns.
-- Authenticated clients keep read/delete access to their own history but cannot
-- forge assistant messages or rewrite prior turns through the REST API.

drop policy if exists chat_messages_self_insert on public.chat_messages;
drop policy if exists chat_messages_self_update on public.chat_messages;

comment on table public.chat_messages is
  'Conversation history written only by the verified chat Edge Function; users may read/delete their own rows.';
