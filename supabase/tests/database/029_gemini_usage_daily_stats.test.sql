create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

select has_function('public', 'gemini_usage_daily_stats', 'gemini_usage_daily_stats 함수 존재');

select is(
  has_function_privilege('anon', 'public.gemini_usage_daily_stats(date)', 'EXECUTE'),
  false, 'anon 은 Gemini 사용량 RPC 를 실행할 수 없다');
select is(
  has_function_privilege('authenticated', 'public.gemini_usage_daily_stats(date)', 'EXECUTE'),
  true, 'authenticated 는 실행 권한은 있다(관리자 여부는 함수 내부에서 판정)');

-- ── 시드 ────────────────────────────────────────────────────────
-- "오늘"에 걸리는 로우와 "고정된 과거 달"에 걸리는 로우를 분리한다 — 실행일이
-- 매달 1일이면 date_trunc('month', now()) - interval '1 day' 가 "오늘"과
-- 다른 로우인데도 같은 날짜 버킷에 들어갈 수 있어, now() 기준 로우끼리
-- 섞으면 CI 실행일에 따라 플래키해진다(pgTAP 날짜경계 함정).
delete from public.gemini_usage where context = 'test-029';

insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'gemini-member@test.local')
on conflict do nothing;
insert into public.users (id, email, name) values
  ('66666666-6666-6666-6666-666666666666', 'gemini-member@test.local', '일반회원')
on conflict (id) do update set name = excluded.name;

-- 오늘 요청 2건(kind 다름) — "인자 없으면 이번 달=오늘 포함" 검증용.
insert into public.gemini_usage (created_at, kind, model, input_tokens, output_tokens, total_tokens, context) values
  (now(), 'llm', 'gemini-3.1-flash-lite', 100, 50, 150, 'test-029'),
  (now(), 'embedding', 'gemini-embedding-2', 20, 0, 20, 'test-029');

-- 고정된 과거 달(2년 전 6월) 이틀에 걸쳐 3건 — p_month 명시 조회·날짜별 분리
-- 검증용. "오늘"과 절대 안 겹치므로 실행일과 무관하게 결정적이다.
insert into public.gemini_usage (created_at, kind, model, input_tokens, output_tokens, total_tokens, context) values
  ('2024-06-01 03:00:00+09', 'llm', 'gemini-3.1-flash-lite', 10, 5, 15, 'test-029'),
  ('2024-06-01 09:00:00+09', 'embedding', 'gemini-embedding-2', 1, 0, 1, 'test-029'),
  ('2024-06-02 03:00:00+09', 'llm', 'gemini-3.1-flash-lite', 20, 10, 30, 'test-029');

-- ── 비관리자는 거부 ────────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims to '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

select throws_ok(
  $$select * from public.gemini_usage_daily_stats()$$,
  'P0001',
  'forbidden: admin only',
  '일반 회원은 Gemini 사용량 집계를 조회할 수 없다'
);

reset role;
reset request.jwt.claims;

-- ── 관리자: 인자 없으면 오늘(이번 달) 데이터를 반환 ─────────────
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';

select is(
  (select sum(request_count)::int from public.gemini_usage_daily_stats()
     where usage_date = (now() at time zone 'Asia/Seoul')::date),
  2, '인자 없으면 오늘 요청 2건(llm 1 + embedding 1)이 합산된다'
);

-- ── 관리자: p_month 로 고정 과거 달 조회 시 날짜별로 분리·합산 ──
select is(
  (select count(*)::int from public.gemini_usage_daily_stats('2024-06-01'::date)),
  2, '2024-06 조회 시 데이터가 있던 이틀(6/1, 6/2)만 행으로 나온다'
);

select is(
  (select request_count::int from public.gemini_usage_daily_stats('2024-06-01'::date)
     where usage_date = '2024-06-01'),
  2, '6/1 하루에 걸린 llm+embedding 2건이 합산된다'
);

select is(
  (select total_tokens::int from public.gemini_usage_daily_stats('2024-06-01'::date)
     where usage_date = '2024-06-02'),
  30, '6/2 는 6/1 과 별개 행으로 집계된다(날짜 버킷 분리)'
);

reset role;
reset request.jwt.claims;

delete from public.gemini_usage where context = 'test-029';

select * from finish();
rollback;
