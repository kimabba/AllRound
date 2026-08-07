create extension if not exists pgtap with schema extensions;

begin;
select plan(18);

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

select ok(
  has_column_privilege('authenticated', 'public.club_chat_messages', 'thread_id', 'INSERT')
  and has_column_privilege('authenticated', 'public.club_chat_messages', 'sender_id', 'INSERT')
  and has_column_privilege('authenticated', 'public.club_chat_messages', 'body', 'INSERT'),
  '로그인 사용자는 메시지 입력값만 쓸 수 있다'
);
select ok(
  not has_column_privilege('authenticated', 'public.club_chat_messages', 'id', 'INSERT'),
  '로그인 사용자는 메시지 ID를 위조할 수 없다'
);
select ok(
  not has_column_privilege('authenticated', 'public.club_chat_messages', 'created_at', 'INSERT'),
  '로그인 사용자는 메시지 작성 시각을 위조할 수 없다'
);
select alike(
  (select with_check from pg_policies
   where schemaname = 'public'
     and tablename = 'club_chat_messages'
     and policyname = 'club_chat_messages_insert'),
  '%has_accepted_current_ugc_terms%',
  '채팅 작성은 최신 UGC 약관 동의를 요구한다'
);
select alike(
  (select with_check from pg_policies
   where schemaname = 'public'
     and tablename = 'club_chat_messages'
     and policyname = 'club_chat_messages_insert'),
  '%has_active_ugc_penalty%',
  '채팅 작성은 커뮤니티 제재를 확인한다'
);

select * from finish();
rollback;
