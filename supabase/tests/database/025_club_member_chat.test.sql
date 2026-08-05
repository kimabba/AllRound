create extension if not exists pgtap with schema extensions;

begin;
select plan(13);

select has_table('public', 'club_chat_threads', '모임 채팅방 테이블 존재');
select has_table('public', 'club_chat_participants', '1:1 참여자 테이블 존재');
select has_table('public', 'club_chat_messages', '모임 메시지 테이블 존재');

select is(
  (select relrowsecurity from pg_class where oid = 'public.club_chat_threads'::regclass),
  true,
  '채팅방 RLS 활성화'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.club_chat_participants'::regclass),
  true,
  '참여자 RLS 활성화'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.club_chat_messages'::regclass),
  true,
  '메시지 RLS 활성화'
);

select has_function(
  'public', 'can_access_club_chat', array['uuid'],
  '채팅 접근 권한 함수 존재'
);
select has_function(
  'public', 'open_club_chat', array['uuid', 'uuid'],
  '채팅방 열기 함수 존재'
);

select policies_are(
  'public', 'club_chat_threads',
  array['club_chat_threads_read'],
  '채팅방은 허용된 멤버만 읽는다'
);
select policies_are(
  'public', 'club_chat_participants',
  array['club_chat_participants_read'],
  '1:1 참여자는 허용된 멤버만 읽는다'
);
select policies_are(
  'public', 'club_chat_messages',
  array['club_chat_messages_insert', 'club_chat_messages_read'],
  '메시지는 허용된 멤버만 읽고 쓴다'
);

select col_is_pk(
  'public', 'club_chat_participants', array['thread_id', 'user_id'],
  '대화 참여자는 중복될 수 없다'
);
select col_type_is(
  'public', 'club_chat_messages', 'body', 'text',
  '메시지 본문은 text 타입이다'
);

select * from finish();
rollback;
