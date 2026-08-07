-- 운영 환경의 함수 기본 권한이 anon/authenticated 에 직접 EXECUTE 를 부여하므로,
-- 채팅 SECURITY DEFINER 함수의 실제 호출 주체를 명시적으로 제한한다.

begin;

revoke execute on function public.can_access_club_chat(uuid)
  from public, anon;
revoke execute on function public.open_club_chat(uuid, uuid)
  from public, anon;

revoke execute on function public.touch_club_chat_thread()
  from public, anon, authenticated;
revoke execute on function public.notify_club_chat_message()
  from public, anon, authenticated;

grant execute on function public.can_access_club_chat(uuid)
  to authenticated, service_role;
grant execute on function public.open_club_chat(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.touch_club_chat_thread()
  to service_role;
grant execute on function public.notify_club_chat_message()
  to service_role;

commit;
