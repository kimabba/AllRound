-- 보안 수정: invoke_edge_function 이 INTERNAL_CRON_JWT 를 SQL 하드코딩 대신
-- Vault(`vault.decrypted_secrets`)에서 읽도록 교체한다.
--
-- 030 마이그레이션이 service_role JWT 를 평문으로 포함해 공개 레포에 노출되었음.
-- 적용 전 필수: 새로 발급한 JWT 를 Vault 에 저장
--   select vault.create_secret('<new_internal_cron_jwt>', 'internal_cron_jwt');

create or replace function public.invoke_edge_function(
  fn_name text,
  body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
as $$
declare
  invoke_url   constant text := 'https://bsjdgwmveokanclqwtvx.supabase.co/functions/v1';
  cron_jwt     text;
  request_id   bigint;
begin
  select decrypted_secret into cron_jwt
  from vault.decrypted_secrets
  where name = 'internal_cron_jwt';

  if cron_jwt is null then
    raise exception 'Vault secret "internal_cron_jwt" 가 설정되지 않았습니다. select vault.create_secret(...) 먼저 실행하세요.';
  end if;

  select net.http_post(
    url     := invoke_url || '/' || fn_name,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || cron_jwt
    ),
    body    := body
  ) into request_id;
  return request_id;
end;
$$;
