-- 014_device_token_cap.sql
-- SEC-M-05 (일부): 사용자당 device_tokens 개수 상한.
--
-- 문제: PK(user_id, token) 라 한 사용자가 위조 토큰을 무제한 등록 가능.
--       notify-cron 이 전부에게 발송 시도 → FCM 호출 폭증.
-- 대응: INSERT 후 최신 updated_at 기준 상위 N개만 유지, 초과분 GC.
--       (토큰은 정상적으로 회전되므로 reject 대신 oldest GC 가 적절)
--
-- chat_messages 길이 제한은 SEC-H-01 (chat 함수 message>4000 거부) 에서 처리됨.
-- chat_messages 90일 retention 은 별도 cron 으로 후속 처리 권장.

create or replace function public.cap_device_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.device_tokens
  where user_id = new.user_id
    and token in (
      select token
      from public.device_tokens
      where user_id = new.user_id
      order by updated_at desc
      offset 10
    );
  return null;
end;
$$;

drop trigger if exists device_tokens_cap on public.device_tokens;

create trigger device_tokens_cap
  after insert on public.device_tokens
  for each row execute function public.cap_device_tokens();

comment on function public.cap_device_tokens is
  '사용자당 device_tokens 최신 10개만 유지 (SEC-M-05 abuse 방지).';
