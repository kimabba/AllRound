-- 랭킹 선수 이력 온디맨드 캐시 (org_player_history_fetches)
--
-- 지키는 것:
--   1) 협회 코드는 지원하는 값만 허용한다.
--   2) 수집 건수는 음수가 될 수 없다.
--   3) 캐시 메타데이터는 클라이언트가 직접 볼 수 없다(service_role 전용).
--
-- 이력 저장 자체(upsert_org_player_results 재사용)는 크롤러 쪽 테스트가 이미
-- 지킨다 — 여기서는 이 테이블 고유의 제약·RLS 만 본다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(5);

set local role postgres;

select throws_ok(
  $$insert into public.org_player_history_fetches
      (org_code, org_player_id, result_count, is_complete)
    values ('zz', 'zz_bad_org', 0, true)$$,
  '23514',
  null,
  '지원하지 않는 협회 코드는 거부한다'
);

select throws_ok(
  $$insert into public.org_player_history_fetches
      (org_code, org_player_id, result_count, is_complete)
    values ('gj', 'zz_negative', -1, true)$$,
  '23514',
  null,
  '음수 수집 건수는 거부한다'
);

insert into public.org_player_history_fetches
  (org_code, org_player_id, result_count, is_complete)
values ('gj', 'zz_history_player', 2, false);

select is(
  (select result_count from public.org_player_history_fetches
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  2,
  'service_role 은 캐시 메타데이터를 저장할 수 있다'
);

select is(
  (select is_complete from public.org_player_history_fetches
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  false,
  '페이지 상한에 닿은 수집은 불완전 상태를 보존한다'
);

reset role;
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.org_player_history_fetches),
  0,
  '로그인 사용자도 캐시 메타데이터를 직접 볼 수 없다'
);

select * from finish();
rollback;
