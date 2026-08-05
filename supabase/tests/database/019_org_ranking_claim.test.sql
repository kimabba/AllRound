create extension if not exists pgtap with schema extensions;

begin;
select plan(15);

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

-- ── 신청(INSERT) 자격은 "내가 등록한 협회·부서"로 제한된다 ─────────────
-- 앱이 랭킹표에서 직접 신청하는 동선이 열려 있으므로(자동 후보 매칭 밖),
-- 자격 강제의 정본은 정책이다. org_player_links 는 PostgREST 직행 테이블이라
-- 앱을 우회한 요청도 여기서만 막힌다.
insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('jn', 'jn_m_gold', 1, '남의협회', 'jn_player', '전남/', 900, 900, 'https://x'),
  ('gj', 'gj_m_gold', 3, '홍길동',   'gildong',   '어등산/', 100, 100, 'https://x'),
  -- 실제 데이터에는 한 협회 안 동명이인이 없다(2026-08-05 실측 0건). 여기서는
  -- '확정 보유자의 추가 신청' 조건만 따로 떼어 보려고 일부러 같은 이름을 하나 더 둔다 —
  -- 이름이 다르면 이름 조건에 먼저 걸려 무엇 때문에 막혔는지 알 수 없다.
  ('gj', 'gj_m_gold', 4, '김평화',   'kimph2',    '어등산/',  90,  90, 'https://x'),
  -- 아래 부서·협회 거부 단언의 신청자는 6666(이기영)이다. 대상 선수 이름이 다르면
  -- 이름 조건에 먼저 걸려 "부서라서 막혔다"를 증명하지 못한다 — 같은 이름으로 둔다.
  ('gj', 'gj_w_rookie', 2, '이기영', 'other2', '다른부서/', 80, 80, 'https://x'),
  ('jn', 'jn_m_gold',   2, '이기영', 'jn_lky', '전남/',     70, 70, 'https://x');

-- status 조건만 격리해 보기 위한 유저(이름이 gildong 과 같다).
insert into auth.users (id, email) values
  ('77777777-7777-7777-7777-777777777777', 'g@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('77777777-7777-7777-7777-777777777777', 'g@test.local', '홍길동')
on conflict (id) do update set name = excluded.name;

insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary) values
  ('77777777-7777-7777-7777-777777777777', 'gj', 'default', array['gj_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

-- 신청자는 아직 확정 연결이 없는 별도 유저를 쓴다. 유저 3333 은 위에서 이미
-- vudghk2116 에 confirmed 가 붙어 있어, 그 상태로는 어느 선수든 신청이 막힌다
-- (협회당 유저 1명 1선수) — 아래에서 그것도 따로 검증한다.
insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'f@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('66666666-6666-6666-6666-666666666666', 'f@test.local', '이기영')
on conflict (id) do update set name = excluded.name;

insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary) values
  ('66666666-6666-6666-6666-666666666666', 'gj', 'default', array['gj_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

set local role authenticated;
set local request.jwt.claims to '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

-- 유저 6666(이기영) 의 등록: gj / gj_m_gold. 이름이 같은 선수는 신청할 수 있다.
select lives_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'lkybks', '66666666-6666-6666-6666-666666666666', 'pending')$$,
  '등록한 협회·부서 안의 선수는 신청할 수 있다');

-- 같은 협회라도 등록하지 않은 부서(gj_w_rookie)의 선수는 막힌다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'other2', '66666666-6666-6666-6666-666666666666', 'pending')$$,
  '42501',
  null,
  '등록하지 않은 부서의 선수는 신청할 수 없다');

-- 등록하지 않은 협회(jn)의 선수도 막힌다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('jn', 'jn_lky', '66666666-6666-6666-6666-666666666666', 'pending')$$,
  '42501',
  null,
  '등록하지 않은 협회의 선수는 신청할 수 없다');

-- 랭킹표에 아예 없는 아이디를 지어내도 막힌다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'made-up-id', '66666666-6666-6666-6666-666666666666', 'pending')$$,
  '42501',
  null,
  '랭킹표에 없는 협회 아이디는 신청할 수 없다');

-- 이름이 다른 선수는 등록 부서 안이어도 신청할 수 없다(Commander 결정 2026-08-05).
-- 한 협회 안 동명이인이 0건이라 이름 하나로 사람이 특정된다.
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'gildong', '66666666-6666-6666-6666-666666666666', 'pending')$$,
  '42501',
  null,
  '이름이 다른 선수는 신청할 수 없다');

reset role;
reset request.jwt.claims;

-- 승인 단계를 건너뛰고 confirmed 로 직접 넣는 건 여전히 막힌다(기존 조건 회귀 방어).
-- 이름·부서·확정 조건을 모두 만족하는 유저(7777 홍길동 → gildong)로 검증해
-- status 조건만 남긴다. 다른 조건에 먼저 걸리면 이 단언은 아무것도 증명하지 못한다.
set local role authenticated;
set local request.jwt.claims to '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated"}';

select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'gildong', '77777777-7777-7777-7777-777777777777', 'confirmed')$$,
  '42501',
  null,
  'confirmed 로 직접 넣을 수 없다 — 승인은 관리자만');

reset role;
reset request.jwt.claims;

-- 이미 이 협회에 확정 연결이 있는 사람은 다른 선수를 신청할 수 없다.
-- org_player_links_confirmed_user_key(협회당 유저 1명 1선수)가 승인 시점에
-- 23505 를 내므로, 받아두면 승인 불가한 대기 건만 관리자 큐에 쌓인다.
set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'kimph2', '33333333-3333-3333-3333-333333333333', 'pending')$$,
  '42501',
  null,
  '이미 확정 연결된 사람은 같은 협회의 다른 선수를 신청할 수 없다');

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims to '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}';

-- 내가 만든 pending 을 스스로 confirmed 로 UPDATE 하는 경로도 없어야 한다.
-- UPDATE 를 허용하는 정책은 org_player_links_admin 뿐이라 에러 없이 0행 갱신으로
-- 끝난다 — 조용히 통과하는 종류라 결과 상태로 확인한다.
update public.org_player_links set status = 'confirmed'
where org_code = 'gj' and org_player_id = 'lkybks'
  and user_id = '66666666-6666-6666-6666-666666666666';

reset role;
reset request.jwt.claims;

select is(
  (select status from public.org_player_links
   where org_code = 'gj' and org_player_id = 'lkybks'
     and user_id = '66666666-6666-6666-6666-666666666666'),
  'pending', '본인 신청을 스스로 승인으로 바꿀 수 없다');

select * from finish();
rollback;
