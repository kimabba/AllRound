create extension if not exists pgtap with schema extensions;

begin;
select plan(26);

-- ── 표·권한 ────────────────────────────────────────────────────────────────
select has_table('public', 'edge_invocations', 'edge_invocations 표가 있다');
select col_is_pk('public', 'edge_invocations', 'id', 'PK 는 대리키 id 다 — request_id 는 pg_net 시퀀스 리셋으로 재사용될 수 있다');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.edge_invocations'::regclass),
  'edge_invocations 에 RLS 가 켜져 있다'
);

select is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'edge_invocations'),
  0,
  '정책이 없다 — 운영 로그이므로 클라이언트 역할에는 열지 않는다'
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

-- CREATE OR REPLACE 는 ACL 을 보존하므로, 한 번 새면 재적용으로 복구되지 않는다.
select ok(
  not has_function_privilege('anon', 'public.invoke_edge_function(text,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.invoke_edge_function(text,jsonb)', 'execute'),
  'anon·authenticated 는 invoke_edge_function 을 실행할 수 없다 — Vault 의 내부 cron JWT 로 임의 Edge 함수를 호출할 수 있게 된다'
);

-- 부정 가드만 있으면 service_role grant 가 사라져도 녹색이다(011 지문 위반).
select ok(
  has_function_privilege('service_role', 'public.invoke_edge_function(text,jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.sweep_edge_invocations()', 'execute'),
  'service_role 은 두 함수를 실행할 수 있다 — 권한 지문의 요구'
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

-- 이름·주기만 보면 명령을 `select 1` 로 바꿔 자동 스윕을 끊어도 녹색이다.
select ok(
  exists(
    select 1 from cron.job
     where jobname = 'edge-invocation-sweep'
       and active
       and command like '%sweep_edge_invocations()%'
  ),
  'cron 이 실제로 sweep_edge_invocations() 를 호출한다 — 이름·주기만 보면 빈 명령도 통과한다'
);

-- ── 스윕 동작 ──────────────────────────────────────────────────────────────
-- 1) 응답이 도착한 호출
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900001, 'test-fn-failed', now() - interval '1 minute');
-- error_msg·timed_out 을 non-null 로 둔다. null fixture 였을 때는 그 두 컬럼의 복사를
-- 통째로 지워도 테스트가 통과했다.
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900001, 500, 'boom from edge', true, now() - interval '1 minute');

-- 2) 응답이 아직 없는 최근 호출: 건드리지 않는다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900002, 'test-fn-inflight', now() - interval '1 minute');

-- 3) 8시간이 지나도록 응답이 없는 호출: 유실로 확정한다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900003, 'test-fn-lost', now() - interval '9 hours');

-- 4) 14일이 지난 기록: outcome 과 무관하게 삭제된다.
--    response 만 두면 '삭제를 response 전용으로' 망가뜨려도 통과한다 — 그러면 오래된
--    pending·lost 가 영원히 쌓인다.
insert into public.edge_invocations (request_id, fn_name, invoked_at, outcome, status_code, settled_at)
values (900004, 'test-fn-old-response', now() - interval '15 days', 'response', 200, now() - interval '15 days'),
       (900006, 'test-fn-old-pending',  now() - interval '15 days', 'pending', null, null),
       (900007, 'test-fn-old-lost',     now() - interval '16 days', 'lost',    null, now() - interval '16 days');

-- 5) 전송 오류/타임아웃 응답: pg_net 은 이것도 **완료된 응답**으로 남기며 status_code 가 null 이다
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900005, 'test-fn-transport-error', now() - interval '2 minutes');
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900005, null, 'Timeout was reached', true, now() - interval '1 minute');

-- 반환값 = 이번 스윕이 확정한 건수. lives_ok 로 두면 '몇 건을 건드렸는가'를 못 본다.
-- 응답 2건(900001·900005 전송오류) + 만료 2건(900003 · 900006 은 15일 지난 pending 이라
-- 만료로 세어진 뒤 같은 스윕의 14일 삭제로 사라진다).
select is(
  (select public.sweep_edge_invocations()),
  4,
  '스윕이 이번에 확정한 건수는 4 — 응답 2건 + 만료 2건'
);

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

select is(
  (select outcome from public.edge_invocations where request_id = 900002),
  'pending',
  '아직 응답이 없는 최근 호출은 pending 으로 남는다'
);

select is(
  (select format('%s|%s', outcome, error_msg) from public.edge_invocations where request_id = 900003),
  'lost|no response row (pg_net retention passed)',
  '8시간이 지난 미해결 호출은 유실로 확정된다 — 조용히 pending 으로 두면 실패 없음으로 오독된다'
);

select is(
  (select count(*)::integer from public.edge_invocations where request_id in (900004, 900006, 900007)),
  0,
  '14일이 지난 기록은 outcome 과 무관하게 삭제된다'
);

-- 전송 오류 응답은 status_code 가 null 이어도 '응답 받음'으로 확정돼야 한다.
-- status_code is null 을 미해결로 보면 이 행을 10분마다 영원히 다시 갱신한다.
select is(
  (select outcome from public.edge_invocations where request_id = 900005),
  'response',
  'status_code 가 null 인 전송 오류 응답도 응답으로 확정된다'
);

-- 6) 유실로 확정한 뒤 응답이 늦게 도착하면(pg_net worker 정체 등) 그때라도 붙어야 한다.
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900003, 200, null, false, now());

-- 두 번째 스윕이 확정할 것은 900003(늦게 온 응답) 하나뿐이어야 한다.
-- 이미 확정된 행을 다시 집으면 여기서 2 이상이 된다 — settled_at 비교로는 이 결함을 못 잡는다
-- (같은 트랜잭션 안에서 now() 가 고정이라 두 번 갱신해도 값이 같다. 실제로 거짓 통과했다).
select is(
  (select public.sweep_edge_invocations()),
  1,
  '두 번째 스윕은 늦게 도착한 응답 1건만 확정한다 — 확정된 행을 다시 집지 않는다'
);

select is(
  (select format('%s|%s', outcome, status_code) from public.edge_invocations where request_id = 900003),
  'response|200',
  '유실로 확정한 뒤 도착한 응답도 반영된다 — 만료가 최종 판정이 되면 안 된다'
);

-- ── 발사 기록 ──────────────────────────────────────────────────────────────
-- 스윕이 아무리 정확해도 invoke_edge_function 이 기록을 남기지 않으면 전부 무의미하다.
-- net.http_post 는 큐에 넣기만 하므로(비동기) 로컬에서도 안전하게 호출된다.
-- vault.secrets 직접 INSERT 는 pgsodium 권한(_crypto_aead_det_noncegen)에 막힌다 → 함수로 넣는다.
select vault.create_secret('test-only-not-a-real-jwt', 'internal_cron_jwt')
where not exists (select 1 from vault.secrets where name = 'internal_cron_jwt');

-- 아래 재사용 테스트가 시퀀스를 되감으므로(setval 은 롤백되지 않는다) 원래 값을 보관했다가
-- 파일 끝에서 되돌린다.
create temp table seq_backup on commit drop as
select last_value, is_called from net.http_request_queue_id_seq;

create temp table invoke_probe on commit drop as
select public.invoke_edge_function('observability-selftest') as request_id;

select ok(
  exists(
    select 1 from public.edge_invocations e
    join invoke_probe p on p.request_id = e.request_id
    where e.fn_name = 'observability-selftest' and e.outcome = 'pending'
  ),
  'invoke_edge_function 이 호출 즉시 request_id·함수명을 남긴다 — 이게 없으면 응답을 누구에게도 붙일 수 없다'
);

-- 위 어서션만으로는 "기록은 남기되 발사는 하지 않는" 변이를 못 잡는다.
-- 주소는 접미사가 아니라 전체를 맞춘다(호스트·프로젝트가 틀려도 통과하면 안 된다).
select ok(
  exists(
    select 1 from net.http_request_queue q
    join invoke_probe p on p.request_id = q.id
    where q.url = 'https://bsjdgwmveokanclqwtvx.supabase.co/functions/v1/observability-selftest'
      and q.headers ->> 'Authorization' like 'Bearer %'
      and length(q.headers ->> 'Authorization') > length('Bearer ')
  ),
  '기록과 함께 실제 요청이 큐에 들어간다(정확한 주소 + 비어 있지 않은 Bearer 토큰)'
);

-- ── 재사용된 request_id ────────────────────────────────────────────────────
-- 시퀀스가 되감겨 과거 번호가 다시 나와도 (a) 예외로 전달을 취소하지 않고
-- (b) 과거 기록을 파괴하지 않아야 한다.
--
-- 같은 번호에 이미 끝난 행(response)과 아직 대기 중인 행(pending)을 **둘 다** 둔다.
-- response 만 두면 충돌 경로 자체를 안 타서, DO UPDATE 를 DO NOTHING 으로 망가뜨려도
-- 통과한다(codex 지적). pending 행이 있어야 자리 양보(superseded)가 실제로 검증된다.
insert into public.edge_invocations (request_id, fn_name, invoked_at, outcome, status_code, settled_at)
values (900020, 'old-settled-owner', now() - interval '3 days', 'response', 200, now() - interval '3 days'),
       (900020, 'old-pending-owner', now() - interval '2 hours', 'pending', null, null);

select setval('net.http_request_queue_id_seq', 900019, true);

create temp table reuse_probe on commit drop as
select public.invoke_edge_function('reused-id-probe') as request_id;

select is(
  (select string_agg(format('%s:%s', fn_name, outcome), ',' order by fn_name)
     from public.edge_invocations where request_id = 900020),
  'old-pending-owner:superseded,old-settled-owner:response,reused-id-probe:pending',
  '번호가 재사용되면 옛 pending 은 superseded 로 자리를 비키고 새 행이 생긴다 — 과거 기록은 지워지지 않는다'
);

-- 오귀속 방지: 같은 번호에 옛 lost 와 새 pending 이 함께 있을 때, 도착한 응답은
-- **가장 최근 호출**의 것이다. 옛 실패 기록에 붙으면 실패가 성공으로 둔갑한다.
insert into public.edge_invocations (request_id, fn_name, invoked_at, outcome, error_msg, settled_at)
values (900030, 'older-lost', now() - interval '2 days', 'lost',
        'no response row (pg_net retention passed)', now() - interval '2 days');
insert into public.edge_invocations (request_id, fn_name, invoked_at)
values (900030, 'newer-pending', now() - interval '3 minutes');
insert into net._http_response (id, status_code, error_msg, timed_out, created)
values (900030, 204, null, false, now());

select public.sweep_edge_invocations();

select is(
  (select string_agg(format('%s:%s', fn_name, outcome), ',' order by fn_name)
     from public.edge_invocations where request_id = 900030),
  'newer-pending:response,older-lost:lost',
  '도착한 응답은 가장 최근 호출에만 붙는다 — 옛 실패 기록이 성공으로 둔갑하지 않는다'
);

-- 한 번의 스윕만 보면 부족하다. 응답 행은 pg_net 보존 동안 남아 다음 스윕에도 다시 보인다.
-- 최신 행이 response 가 된 뒤 남은 옛 lost 가 새 최댓값이 되어 같은 응답을 또 집어가는지
-- 확인해야 실제 10분 주기 동작을 검증한 것이다(codex 지적).
select is(
  (select public.sweep_edge_invocations()),
  0,
  '같은 응답이 남아 있어도 다음 스윕은 아무것도 새로 확정하지 않는다'
);

select is(
  (select outcome from public.edge_invocations where request_id = 900030 and fn_name = 'older-lost'),
  'lost',
  '두 번째 스윕에서도 옛 실패 기록은 lost 로 남는다 — 응답 하나가 세대를 거슬러 재사용되지 않는다'
);

select setval('net.http_request_queue_id_seq',
              (select last_value from seq_backup),
              (select is_called from seq_backup));

select * from finish();
rollback;
