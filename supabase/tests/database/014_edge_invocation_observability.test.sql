create extension if not exists pgtap with schema extensions;

begin;
select plan(20);

-- ── 표·권한 ────────────────────────────────────────────────────────────────
select has_table('public', 'edge_invocations', 'edge_invocations 표가 있다');
select col_is_pk('public', 'edge_invocations', 'request_id', 'request_id 가 PK — 같은 요청이 두 번 기록되지 않는다');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.edge_invocations'::regclass),
  'edge_invocations 에 RLS 가 켜져 있다'
);

select is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'edge_invocations'),
  0,
  '정책이 없다 — 운영 로그이므로 service_role 만 접근한다'
);

-- 권한은 지문대로 넓게 준다(011 가드). 실제 차단은 정책이 0개라는 사실이 한다.
-- 권한 유무가 아니라 **실제로 한 행도 안 보이는지**를 확인한다.
insert into public.edge_invocations (request_id, fn_name)
values (900010, 'visibility-probe');

set local role authenticated;
select is(
  (select count(*)::integer from public.edge_invocations),
  0,
  'authenticated 는 권한이 있어도 RLS 정책이 없어 한 행도 보지 못한다'
);
reset role;

select ok(
  not has_function_privilege('anon', 'public.sweep_edge_invocations()', 'execute')
  and not has_function_privilege('authenticated', 'public.sweep_edge_invocations()', 'execute'),
  'anon·authenticated 는 스윕을 실행할 수 없다'
);

-- ── cron ───────────────────────────────────────────────────────────────────
select is(
  (select count(*)::integer from cron.job where jobname = 'edge-invocation-sweep'),
  1,
  'edge-invocation-sweep cron 이 정확히 하나다'
);

select is(
  (select schedule from cron.job where jobname = 'edge-invocation-sweep'),
  '*/10 * * * *',
  '스윕은 10분마다 돈다 — pg_net 보존(약 6시간)보다 훨씬 잦아야 응답을 놓치지 않는다'
);

-- ── 스윕 동작 ──────────────────────────────────────────────────────────────
-- 1) 응답이 도착한 호출: 상태코드가 붙고 settled 된다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900001, 'test-fn-failed', now() - interval '1 minute');
-- error_msg·timed_out 을 non-null 로 둔다. null fixture 였을 때는 그 두 컬럼의 복사를
-- 통째로 지워도 테스트가 통과했다(codex 지적).
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900001, 500, 'boom from edge', true, now() - interval '1 minute');

-- 2) 응답이 아직 없는 최근 호출: 건드리지 않는다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900002, 'test-fn-inflight', now() - interval '1 minute');

-- 3) 8시간이 지나도록 응답이 없는 호출: 유실로 확정한다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900003, 'test-fn-lost', now() - interval '9 hours');

-- 4) 14일이 지난 기록: 삭제된다
insert into public.edge_invocations (request_id, fn_name, invoked_at, status_code, settled_at)
values (900004, 'test-fn-old', now() - interval '15 days', 200, now() - interval '15 days');

select lives_ok('select public.sweep_edge_invocations()', '스윕이 실행된다');

select is(
  (select status_code from public.edge_invocations where request_id = 900001),
  500,
  '도착한 응답의 상태코드가 기록된다 — cron 은 succeeded 였어도 500 이 남는다'
);

select is(
  (select format('%s|%s', error_msg, timed_out::text) from public.edge_invocations where request_id = 900001),
  'boom from edge|true',
  '에러 메시지와 타임아웃 여부도 함께 복사된다 — 상태코드만으로는 원인을 못 좁힌다'
);

select ok(
  (select settled_at is null from public.edge_invocations where request_id = 900002),
  '아직 응답이 없는 최근 호출은 미해결로 남는다'
);

select ok(
  (select settled_at is not null and error_msg like 'no response row%'
     from public.edge_invocations where request_id = 900003),
  '8시간이 지난 미해결 호출은 유실로 확정된다 — 조용히 미해결로 두면 실패 없음으로 오독된다'
);

select is(
  (select count(*)::integer from public.edge_invocations where request_id = 900004),
  0,
  '14일이 지난 기록은 삭제된다'
);

-- 5) 유실로 확정한 뒤 응답이 늦게 도착하면(pg_net worker 정체 등) 그때라도 붙어야 한다.
--    settled 기준으로 걸렀다면 이 행은 영원히 '유실'로 남는다.
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900003, 200, null, false, now());

select lives_ok('select public.sweep_edge_invocations()', '스윕이 다시 실행된다');

select is(
  (select status_code from public.edge_invocations where request_id = 900003),
  200,
  '유실로 확정한 뒤 도착한 응답도 반영된다 — 만료가 최종 판정이 되면 안 된다'
);

-- ── 발사 기록 ──────────────────────────────────────────────────────────────
-- 스윕이 아무리 정확해도 invoke_edge_function 이 기록을 남기지 않으면 전부 무의미하다.
-- net.http_post 는 큐에 넣기만 하므로(비동기) 로컬에서도 안전하게 호출된다.
-- vault.secrets 직접 INSERT 는 pgsodium 권한(_crypto_aead_det_noncegen)에 막힌다 → 함수로 넣는다.
select vault.create_secret('test-only-not-a-real-jwt', 'internal_cron_jwt')
where not exists (select 1 from vault.secrets where name = 'internal_cron_jwt');

create temp table invoke_probe on commit drop as
select public.invoke_edge_function('observability-selftest') as request_id;

select ok(
  exists(
    select 1 from public.edge_invocations e
    join invoke_probe p on p.request_id = e.request_id
    where e.fn_name = 'observability-selftest' and e.settled_at is null
  ),
  'invoke_edge_function 이 호출 즉시 request_id·함수명을 남긴다 — 이게 없으면 응답을 누구에게도 붙일 수 없다'
);

-- 위 어서션만으로는 "기록은 남기되 발사는 하지 않는" 변이를 못 잡는다(codex 지적).
-- 큐에 실제 요청이 들어갔는지, 주소와 인증 헤더가 붙었는지까지 본다.
select ok(
  exists(
    select 1 from net.http_request_queue q
    join invoke_probe p on p.request_id = q.id
    where q.url like '%/functions/v1/observability-selftest'
      and q.headers ? 'Authorization'
  ),
  '기록과 함께 실제 요청이 큐에 들어간다(주소·Authorization 포함) — 기록만 남기는 변이를 잡는다'
);

-- ── 권한 상승 가드 ─────────────────────────────────────────────────────────
-- CREATE OR REPLACE 는 ACL 을 보존하므로, 한 번 새면 재적용으로 복구되지 않는다.
select ok(
  not has_function_privilege('anon', 'public.invoke_edge_function(text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.invoke_edge_function(text,jsonb)', 'execute'),
  'anon·authenticated 는 invoke_edge_function 을 실행할 수 없다 — Vault 의 내부 cron JWT 로 임의 Edge 함수를 호출할 수 있게 된다'
);

-- ── 재사용된 request_id ────────────────────────────────────────────────────
-- net.http_request_queue 와 그 시퀀스는 UNLOGGED 라(실측 relpersistence='u') 비정상 종료 후
-- id 가 처음부터 다시 발급된다. 보존 중인 기록과 번호가 겹칠 때 예외를 던지면 관측 때문에
-- 전달이 취소된다. 시퀀스를 되감아 그 상황을 만든다(시퀀스 변경은 롤백되지 않지만,
-- 되감긴 번호는 아래 ON CONFLICT 로 흡수되므로 로컬 DB 에 해가 없다).
insert into public.edge_invocations (request_id, fn_name, invoked_at, status_code, settled_at)
values (900020, 'stale-owner-of-reused-id', now() - interval '3 days', 500, now() - interval '3 days');

select setval('net.http_request_queue_id_seq', 900019, true);

create temp table reuse_probe on commit drop as
select public.invoke_edge_function('reused-id-probe') as request_id;

select is(
  (select format('%s|%s|%s', fn_name, (status_code is null)::text, (settled_at is null)::text)
     from public.edge_invocations where request_id = 900020),
  'reused-id-probe|true|true',
  '재사용된 request_id 는 예외 없이 새 호출로 덮인다 — 관측이 실제 전달을 막으면 안 된다'
);

select * from finish();
rollback;
