-- 개인 기록장 — 테이블 격리와 스냅샷 적재 (#JY 개인기록장 1단계)
--
-- 지키는 것 셋:
--   1) 내 전적만 보인다 (남의 org_player_id 행은 안 보인다)
--   2) anon 조회가 에러가 아니라 0행이다 (#365 함정)
--   3) 랭킹 교체가 스냅샷을 남기고, 같은 날 두 번 돌아도 행이 안 는다

create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

-- ── 픽스처: 두 사용자, 각자 다른 협회 선수에 연결 ────────────────
set local role postgres;

insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'zz_mine',   '00000000-0000-4000-8000-000000000002', 'confirmed'),
       ('gj', 'zz_theirs', '00000000-0000-4000-8000-000000000003', 'confirmed');

-- org_rankings.division_code 는 tennis_divisions(code) FK 다. 실제 카탈로그를
-- 오염시키지 않도록 격리용 부서를 하나 임시로 넣는다(트랜잭션 롤백으로 사라진다).
insert into public.tennis_divisions (code, org_code, label_ko)
values ('zz_div', 'gj', 'zz 테스트 부서');

insert into public.org_player_results
  (org_code, org_player_id, tournament_name, played_on, event_raw, result_raw, result_round, points)
values ('gj', 'zz_mine',   'zz 내 대회',   '2026-05-01', '골드부', '1',    1,    1000),
       ('gj', 'zz_mine',   'zz 내 대회2',  '2026-06-01', '골드부', '16강', 16,   60),
       ('gj', 'zz_theirs', 'zz 남의 대회', '2026-05-01', '골드부', '1',    1,    1000);

-- 1) 내 전적만 보인다
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.org_player_results),
  2,
  '연결 승인된 본인 전적 2건만 보인다'
);

-- 2) 남의 행은 안 보인다
select is(
  (select count(*)::int from public.org_player_results where org_player_id = 'zz_theirs'),
  0,
  '남의 org_player_id 전적은 보이지 않는다'
);

-- 3) anon 은 에러가 아니라 0행이다
reset role;
set local role anon;
select is(
  (select count(*)::int from public.org_player_results),
  0,
  'anon 은 전적을 0행으로 본다 (42501 로 죽지 않는다)'
);
select is(
  (select count(*)::int from public.org_ranking_snapshots),
  0,
  'anon 은 스냅샷을 0행으로 본다 (42501 로 죽지 않는다)'
);

-- 4) 랭킹 교체가 스냅샷을 남긴다
--    `perform` 은 plpgsql 전용이라 .sql 파일에서 쓰면 문법 오류다. 평범한 select 로 부른다.
reset role;
set local role postgres;
select public.replace_org_ranking_division(
  'gj', 'zz_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz선수","org_player_id":"zz_mine",
     "club_raw":null,"rank_points":100,"total_points":100}]'::jsonb
);
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  1,
  '부서 교체가 오늘자 스냅샷 1행을 남긴다'
);

-- 5) 같은 날 두 번 돌아도 안 는다
select public.replace_org_ranking_division(
  'gj', 'zz_div', 'https://example.test/zz',
  '[{"rank":2,"player_name":"zz선수","org_player_id":"zz_mine",
     "club_raw":null,"rank_points":90,"total_points":90}]'::jsonb
);
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  1,
  '같은 날 재크롤해도 스냅샷 행이 늘지 않는다'
);

select * from finish();
rollback;
