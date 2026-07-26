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

-- 스윕이 찾는 것은 "아직 응답이 안 붙은 행"이다. settled_at 이 아니라 status_code 기준인
-- 이유는 아래 sweep 주석 참조(만료 확정된 행에도 응답이 늦게 도착할 수 있다).
create index if not exists edge_invocations_pending_idx
  on public.edge_invocations (invoked_at)
  where status_code is null;

-- 운영 로그다. 앱에서 읽을 일이 없다 → RLS 를 켜고 **정책을 하나도 두지 않는다**.
-- 권한을 회수하는 대신 이렇게 하는 이유: 이 프로젝트의 권한 모델은
-- "테이블 권한은 넓게 + RLS 가 행 단위로 통제"다(20260724060000_codify_api_role_grants.sql).
-- 여기서만 권한을 회수하면 지문이 어긋나 클린 재생 시 011 가드가 깨진다.
--
-- 차단 범위를 정확히 적는다: 정책이 0개이므로 **anon·authenticated 는 한 행도 보지 못한다**.
-- service_role 은 예외다 — Supabase 의 service_role 은 rolbypassrls=true 라(운영 실측)
-- RLS 자체를 우회한다. 이 표에 한정된 이야기가 아니라 모든 표가 그렇고, 운영 조회는
-- 그 경로로 한다. 즉 "아무도 못 본다"가 아니라 "클라이언트 역할은 못 본다"가 맞다.
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
  req_id   bigint;
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
  ) into req_id;

  -- 여기서 실패하면 cron 도 실패한다. 그게 맞다 — 기록이 안 되는 상태를
  -- 성공으로 넘기면 다시 관측 공백이 생긴다.
  --
  -- 다만 PK 충돌만은 예외로 흡수한다. net.http_request_queue 와 그 시퀀스는 UNLOGGED 라
  -- (실측: relpersistence='u') 비정상 종료 후 id 가 처음부터 다시 발급된다. 그러면 보존
  -- 중인 14일치 기록과 번호가 겹칠 수 있고, 그때 PK 충돌로 예외를 던지면 **관측 때문에
  -- 실제 전달이 취소된다** — 크롤·알림이 통째로 멈춘다. 관측이 기능을 죽이면 안 된다.
  -- 재사용된 번호는 새 호출의 것이므로 옛 기록을 덮는다(옛 응답은 어차피 붙일 수 없다).
  insert into public.edge_invocations (request_id, fn_name)
  values (req_id, fn_name)
  on conflict (request_id) do update
    set fn_name    = excluded.fn_name,
        invoked_at = now(),
        status_code = null,
        error_msg   = null,
        timed_out   = null,
        settled_at  = null;

  return req_id;
end;
$function$;

-- CREATE OR REPLACE 는 기존 ACL 을 보존한다 → 누가 anon 에 EXECUTE 를 주면 이 마이그레이션을
-- 재적용해도 복구되지 않는다. 이 함수는 Vault 의 내부 cron JWT 로 임의 Edge 함수를 호출할 수
-- 있으므로(권한 상승) 여기서 ACL 을 명시적으로 다시 못박는다. 가드는 014 테스트.
revoke all on function public.invoke_edge_function(text, jsonb) from public, anon, authenticated;
grant execute on function public.invoke_edge_function(text, jsonb) to postgres, service_role;

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
  -- 도착한 응답 붙이기.
  -- 조건이 `settled_at is null` 이 아니라 `status_code is null` 인 이유: 아래 만료 처리로
  -- settled 된 행에도 응답이 늦게 도착할 수 있다(pg_net worker 정체 등). settled 기준으로
  -- 거르면 그 행은 영원히 '유실'로 남아 실제 상태코드를 잃는다.
  with done as (
    update public.edge_invocations e
       set status_code = r.status_code,
           error_msg   = r.error_msg,
           timed_out   = r.timed_out,
           settled_at  = now()
      from net._http_response r
     where r.id = e.request_id
       and e.status_code is null
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

  -- pg_cron 은 job_run_details 를 스스로 지우지 않는다. 운영 실측 29,482행(2026-05-22~),
  -- 연 18만행 추세다. 여기에 스윕이 하나 더 늘었으니 같이 정리한다. 90일이면 사후 조사에
  -- 충분하고, 실패 여부는 이제 edge_invocations 가 보관한다.
  delete from cron.job_run_details where end_time < now() - interval '90 days';

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
