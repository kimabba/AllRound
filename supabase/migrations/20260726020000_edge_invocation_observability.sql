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
-- 하지 않은 것:
--   - 실패 시 알림 발송. 먼저 실패가 *보이는* 상태를 만들고, 실제 패턴을 본 뒤 정한다
--     (현재 알려진 500 원인은 JWT 시계 오차로 자가 회복된다).
--   - cron.job_run_details 정리. 운영 29,482행(2026-05-22~)으로 자동 삭제가 없는 것은
--     사실이지만, 전역 보존 정책은 이 기능의 범위 밖이라 별도로 다룬다.

begin;

-- ── 1) 호출 기록 표 ────────────────────────────────────────────────────────
-- PK 가 request_id 가 **아닌** 이유: net.http_request_queue 와 그 시퀀스는 UNLOGGED 라
-- (실측 relpersistence='u') 비정상 종료 후 id 가 처음부터 다시 발급된다. request_id 를 PK 로
-- 두면 재사용 번호마다 과거 기록을 덮어써 14일 보존이 거짓말이 된다. 대리키를 쓰고,
-- 유일성은 "아직 응답을 못 받은 행"에만 건다(아래 인덱스).
create table if not exists public.edge_invocations (
  id          bigserial   primary key,
  request_id  bigint      not null,     -- net.http_post 가 준 id (= net._http_response.id)
  fn_name     text        not null,
  invoked_at  timestamptz not null default now(),
  -- pending    = 발사했고 응답 대기
  -- response   = 응답이 붙었다(전송 오류·타임아웃 응답 포함 — 그때 status_code 는 null 이다)
  -- lost       = pg_net 보존이 지나도록 응답이 없었다
  -- superseded = 같은 request_id 가 재사용돼 새 호출에 자리를 내줬다(아래 invoke 주석 참조).
  --              결과를 끝내 모른다는 점은 lost 와 같지만 원인이 다르므로 구분한다.
  outcome     text        not null default 'pending'
                          check (outcome in ('pending', 'response', 'lost', 'superseded')),
  status_code integer,
  error_msg   text,
  timed_out   boolean,
  settled_at  timestamptz                -- outcome 이 pending 을 벗어난 시각
);

comment on table public.edge_invocations is
  'cron → Edge Function 호출 결과. invoke_edge_function 이 적고 sweep_edge_invocations 가 채운다. 보존 14일.';

-- 응답을 붙일 대상은 하나로 정해져야 한다 → **아직 응답을 기다리는 행**에 한해 request_id 유일.
-- 끝난 행(response·lost·superseded)은 중복 번호로 남아도 되고, 그래서 번호가 재사용돼도
-- 과거 이력이 살아남는다. 스윕이 응답을 붙일 범위도 이 인덱스와 같다.
--
-- lost 를 유일성 대상에서 빼는 이유: lost 는 "실패했다"는 결론이 난 기록이다. 그걸 재사용
-- 번호가 덮으면 실패를 보이게 하려고 만든 표에서 실패가 사라진다.
create unique index if not exists edge_invocations_open_request_idx
  on public.edge_invocations (request_id)
  where outcome = 'pending';

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
  req_id       bigint;
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
  -- 번호가 재사용됐는데 같은 번호의 pending 행이 남아 있으면, 그 행은 이제 응답을 받을 수
  -- 없다(도착할 응답은 새 호출의 것이다). 그렇다고 덮어쓰면 과거 기록이 사라지므로
  -- **자리만 비켜준다** — superseded 로 확정하고 새 행을 따로 넣는다. 덮어쓰기였다면
  -- 언제 무엇을 불렀는지가 통째로 지워졌을 것이다.
  --
  -- 예외를 던지지 않는 것도 중요하다. 여기서 실패하면 관측 때문에 실제 전달이 취소되어
  -- 크롤·알림이 통째로 멈춘다. 관측이 기능을 죽이면 안 된다.
  update public.edge_invocations
     set outcome    = 'superseded',
         settled_at = now()
   where request_id = req_id
     and outcome = 'pending';

  insert into public.edge_invocations (request_id, fn_name)
  values (req_id, fn_name)
  -- 위 UPDATE 가 자리를 비웠으므로 정상 경로에서는 충돌하지 않는다. 극단적 경합
  -- (같은 번호로 동시 invoke)에서도 예외로 전달을 취소하지 않도록 마지막 방어를 둔다.
  on conflict (request_id) where outcome = 'pending'
  do update
    set fn_name     = excluded.fn_name,
        invoked_at  = now(),
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
  -- 응답 붙이기. 대상은 pending·lost — 아직 응답을 못 받은 행이다.
  -- superseded 는 제외한다: 그 번호로 도착할 응답은 자리를 이어받은 새 호출의 것이다.
  --
  -- `status_code is null` 을 기준으로 삼지 않는 이유: pg_net 은 전송 오류·타임아웃도
  -- **완료된 응답**으로 기록하며 그때 status_code 는 null 이고 error_msg 만 채워진다.
  -- null 을 미해결로 보면 그런 행을 10분마다 영원히 다시 갱신한다.
  --
  -- lost 도 대상에 넣는 이유: 만료로 확정한 뒤에도 응답이 늦게 도착할 수 있다
  -- (pg_net worker 정체 등). 만료가 최종 판정이 되면 실제 상태코드를 영구히 잃는다.
  --
  -- 같은 request_id 를 가진 미해결 행이 둘 이상일 수 있다(번호 재사용으로 옛 lost·superseded
  -- 가 남은 경우). 도착한 응답은 **가장 최근 호출**의 것이므로 id 가 가장 큰 행 하나에만
  -- 붙인다. 그러지 않으면 과거 실패 기록이 새 응답으로 덮여 잘못 귀속된다.
  with done as (
    update public.edge_invocations e
       set status_code = r.status_code,
           error_msg   = r.error_msg,
           timed_out   = r.timed_out,
           outcome     = 'response',
           settled_at  = now()
      from net._http_response r
     where r.id = e.request_id
       and e.outcome in ('pending', 'lost')
       -- 내부 max 는 outcome 으로 거르지 않는다. 거르면 다음 스윕에서 뚫린다:
       -- 최신 행이 response 가 된 뒤에는 남은 옛 lost 가 새로운 최댓값이 되어 같은 응답이
       -- 다시 붙고, 10분마다 과거 실패가 하나씩 성공으로 둔갑한다. 응답은 그 번호의
       -- **최신 세대**의 것이므로, 최신 행이 이미 응답을 받았다면 더 붙일 곳은 없다.
       and e.id = (
             select max(e2.id) from public.edge_invocations e2
              where e2.request_id = e.request_id
           )
    returning 1
  )
  select count(*)::integer into settled from done;

  -- pg_net 보존(약 6시간)이 지나도 응답이 없으면 유실로 확정한다.
  -- 여유를 둬 8시간으로 잡는다(스윕이 몇 번 걸러도 놓치지 않게).
  with gone as (
    update public.edge_invocations
       set outcome    = 'lost',
           error_msg  = coalesce(error_msg, 'no response row (pg_net retention passed)'),
           settled_at = now()
     where outcome = 'pending'
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
