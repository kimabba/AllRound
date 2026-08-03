create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

select has_function('public', 'my_ranking_candidates', '후보 조회 함수 존재');

-- ── 시드 ────────────────────────────────────────────────────────────
-- division_codes 는 user_tennis_orgs 에 있다(users 아님). PK 는 (user_id, org, division).
insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('33333333-3333-3333-3333-333333333333', 'c@test.local', '김평화'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local', '없는이름')
on conflict (id) do update set name = excluded.name;

insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary) values
  ('33333333-3333-3333-3333-333333333333', 'gj', 'default', array['gj_m_gold'], true),
  -- 같은 이름·부서지만 협회가 다른 유저 — 협회 일치 조건 검증용
  ('44444444-4444-4444-4444-444444444444', 'jn', 'default', array['jn_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold',   1, '김평화', 'vudghk2116', '어등산/',   2649, 2649, 'https://x'),
  ('gj', 'gj_m_gold',   2, '이기영', 'lkybks',     '전라/',     2562, 2562, 'https://x'),
  ('gj', 'gj_w_rookie', 1, '김평화', 'other',      '다른부서/',  100,  100, 'https://x');

-- ── 이름 + 협회 + 부서가 모두 맞는 행만 후보 ─────────────────────────
set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select is(
  (select count(*)::int from public.my_ranking_candidates()),
  1, '이름·협회·부서가 맞는 후보 1건만');

select is(
  (select org_player_id from public.my_ranking_candidates()),
  'vudghk2116', '후보의 협회 아이디가 맞다');

-- 앱 모델이 rank_points 를 필수로 읽는다 — 반환에서 빠지면 런타임에 죽는다
select isnt(
  (select rank_points from public.my_ranking_candidates()),
  null, '후보에 rank_points 가 포함된다');

reset role;
reset request.jwt.claims;

-- ── 이미 confirmed 된 선수는 후보에서 빠진다 ─────────────────────────
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'vudghk2116', '33333333-3333-3333-3333-333333333333', 'confirmed');

set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  0, '이미 연결된 선수는 후보에서 제외');
reset role;
reset request.jwt.claims;

-- ── 일치하는 이름이 없는 유저에게 명단이 새지 않는다 ──────────────────
-- (users.name 은 NOT NULL 이라 "이름 없는 유저" 시나리오는 스키마상 불가능하다.
--  대신 랭킹표에 없는 이름 + 다른 협회 유저로 검증한다.)
set local role authenticated;
set local request.jwt.claims to '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  0, '이름·협회가 안 맞는 유저에게 명단이 새지 않는다');
reset role;
reset request.jwt.claims;

-- ── division_codes 오염(자기 org 아닌 코드가 섞임)에도 다른 협회 랭킹이 새지 않는다 ──
-- 온보딩에서 division_codes 가 잘못 채워지는 결함이 실제 있었다(#336/#338).
-- 이 유저는 'jn' 소속인데 division_codes 에 'gj_m_gold'(광주 부서 코드)가 섞여 있다.
-- uto.org = r.org_code 조건이 없으면 division_code 매칭만으로 광주 랭킹이 새어나간다.
insert into auth.users (id, email) values
  ('55555555-5555-5555-5555-555555555555', 'e@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('55555555-5555-5555-5555-555555555555', 'e@test.local', '이기영')
on conflict (id) do update set name = excluded.name;

insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary) values
  ('55555555-5555-5555-5555-555555555555', 'jn', 'default', array['jn_m_gold', 'gj_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

set local role authenticated;
set local request.jwt.claims to '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';
select is(
  (select count(*)::int from public.my_ranking_candidates()),
  0, 'division_codes 가 오염돼도 다른 협회 랭킹이 후보로 새지 않는다');
reset role;
reset request.jwt.claims;

select * from finish();
rollback;
