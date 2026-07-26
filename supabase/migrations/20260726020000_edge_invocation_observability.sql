-- cron → Edge Function 호출 결과 관측 (2026-07-26)
--
-- 문제: cron 은 함수가 실패해도 성공으로 기록한다.
--   `invoke_edge_function` 은 `net.http_post` 의 request_id 를 **반환만 하고 버린다**.
--   pg_net 은 비동기라 http_post 는 "큐에 넣었다"까지만 하고 즉시 성공으로 끝난다.
--   그래서 cron.job_run_details 는 응답과 무관하게 언제나 succeeded 다 — 실측으로
--   crawl-dispatch 576/576 succeeded 인데 Edge 는 500 을 뱉고 있었다.
--
--   응답 자체는 net._http_response 에 남지만 두 가지 이유로 관측에 쓸 수 없다:
--     1) 요청 URL 컬럼이 없다 → 어느 Edge Function 의 응답인지 특정 불가
--        (net.http_request_queue 행은 응답이 오면 삭제된다)
--     2) 보존이 약 6시간이다 → 실측 2026-07-26 13:35 시점에 07:37 이후 것만 존재.
--        아침에 난 실패는 점심이면 사라진다.
--   실제로 지금 net._http_response 에 500 이 4건 있는데 어느 함수인지 알 방법이 없다.
--
-- 해법: 발사 시점에 request_id ↔ 함수명을 우리 표에 남기고, 스윕이 응답을 붙인다.
--   보존이 6시간이므로 스윕은 그보다 훨씬 자주(10분) 돌아야 한다. 6시간이 지나도록
--   응답이 안 붙은 행은 유실로 확정한다 — 조용히 미해결로 남겨두면 "실패가 없다"로
--   오독되기 때문이다.
--
-- 하지 않은 것: 실패 시 알림 발송. 먼저 실패가 *보이는* 상태를 만들고, 실제 실패
--   패턴을 본 뒤에 정한다(현재 알려진 500 원인은 JWT 시계 오차로 자가 회복된다).

begin;

-- ── 1) 호출 기록 표 ────────────────────────────────────────────────────────
create table if not exists public.edge_invocations (
  request_id  bigint primary key,          -- net.http_post 가 준 id (= net._http_response.id)
  fn_name     text        not null,
  invoked_at  timestamptz not null default now(),
  status_code integer,                     -- 응답 도착 후 채워짐
  error_msg   text,
  timed_out   boolean,
  settled_at  timestamptz                  -- null = 아직 응답 미확인
);

comment on table public.edge_invocations is
  'cron → Edge Function 호출 결과. invoke_edge_function 이 적고 sweep_edge_invocations 가 채운다. 보존 14일.';

-- 스윕이 매번 훑는 것은 미해결 행뿐이다.
create index if not exists edge_invocations_unsettled_idx
  on public.edge_invocations (invoked_at)
  where settled_at is null;

-- 운영 로그다. 앱에서 읽을 일이 없다 → RLS 를 켜고 **정책을 하나도 두지 않는다**.
-- 권한을 회수하는 대신 이렇게 하는 이유: 이 프로젝트의 권한 모델은
-- "테이블 권한은 넓게 + RLS 가 행 단위로 통제"다(20260724060000_codify_api_role_grants.sql).
-- 여기서만 권한을 회수하면 지문이 어긋나 클린 재생 시 011 가드가 깨진다.
-- 정책이 0개이므로 anon·authenticated 는 권한이 있어도 한 행도 보지 못한다(테스트로 확인).
alter table public.edge_invocations enable row level security;
grant all on public.edge_invocations to anon, authenticated, service_role;

-- ── 2) 발사 시점 기록 ──────────────────────────────────────────────────────
create or replace function public.invoke_edge_function(fn_name text, body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'vault', 'net'
as $function$
declare
  invoke_url   constant text := 'https://bsjdgwmveokanclqwtvx.supabase.co/functions/v1';
  cron_jwt     text;
  request_id   bigint;
begin
  select decrypted_secret into cron_jwt
  from vault.decrypted_secrets
  where name = 'internal_cron_jwt';

  if cron_jwt is null then
    raise exception 'Vault secret "internal_cron_jwt" 가 설정되지 않았습니다.';
  end if;

  select net.http_post(
    url     := invoke_url || '/' || fn_name,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || cron_jwt
    ),
    body    := body
  ) into request_id;

  -- 여기서 실패하면 cron 도 실패한다. 그게 맞다 — 기록이 안 되는 상태를
  -- 성공으로 넘기면 다시 관측 공백이 생긴다.
  insert into public.edge_invocations (request_id, fn_name)
  values (request_id, fn_name);

  return request_id;
end;
$function$;

-- ── 3) 응답 수거 스윕 ──────────────────────────────────────────────────────
create or replace function public.sweep_edge_invocations()
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'net'
as $function$
declare
  settled integer;
  expired integer;
begin
  -- 도착한 응답 붙이기
  with done as (
    update public.edge_invocations e
       set status_code = r.status_code,
           error_msg   = r.error_msg,
           timed_out   = r.timed_out,
           settled_at  = now()
      from net._http_response r
     where r.id = e.request_id
       and e.settled_at is null
    returning 1
  )
  select count(*)::integer into settled from done;

  -- pg_net 보존(약 6시간)이 지나도 응답이 없으면 유실로 확정한다.
  -- 여유를 둬 8시간으로 잡는다(스윕이 몇 번 걸러도 놓치지 않게).
  with gone as (
    update public.edge_invocations
       set error_msg  = coalesce(error_msg, 'no response row (pg_net retention passed)'),
           settled_at = now()
     where settled_at is null
       and invoked_at < now() - interval '8 hours'
    returning 1
  )
  select count(*)::integer into expired from gone;

  delete from public.edge_invocations where invoked_at < now() - interval '14 days';

  return settled + expired;
end;
$function$;

-- cron 은 postgres 로 돌지만, service_role EXECUTE 는 권한 지문의 요구다(011 가드).
revoke all on function public.sweep_edge_invocations() from public, anon, authenticated;
grant execute on function public.sweep_edge_invocations() to service_role;

-- ── 4) 스윕 cron ───────────────────────────────────────────────────────────
-- 재적용 안전: 같은 이름이 이미 있으면 지우고 다시 건다.
select cron.unschedule(jobid)
from cron.job
where jobname = 'edge-invocation-sweep';

select cron.schedule(
  'edge-invocation-sweep',
  '*/10 * * * *',
  $cron$select public.sweep_edge_invocations();$cron$
);

commit;
