-- 사용자 삭제·변경 시 채팅 외래키 참조 행을 빠르게 찾는다.

create index if not exists club_chat_threads_created_by_idx
  on public.club_chat_threads (created_by);

create index if not exists club_chat_messages_sender_idx
  on public.club_chat_messages (sender_id);
