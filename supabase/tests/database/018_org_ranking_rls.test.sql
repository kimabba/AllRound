create extension if not exists pgtap with schema extensions;

begin;
select plan(14);

-- 테이블 존재
select has_table('public', 'org_rankings', 'org_rankings 테이블 존재');
select has_table('public', 'org_player_links', 'org_player_links 테이블 존재');

-- 죽은 컬럼 제거 확인
select hasnt_column('public', 'user_tennis_orgs', 'ranking_points',
  'user_tennis_orgs.ranking_points 제거됨');

-- RLS 활성화
select is(
  (select relrowsecurity from pg_class where oid = 'public.org_rankings'::regclass),
  true, 'org_rankings RLS enabled');
select is(
  (select relrowsecurity from pg_class where oid = 'public.org_player_links'::regclass),
  true, 'org_player_links RLS enabled');

-- 시드 데이터
insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 1, '김평화', 'vudghk2116', '어등산/', 2649, 2649,
   'https://gjtennis.kr/sub4_5.php?member_kind=골드부'),
  -- 아래 거부 단언들이 "랭킹표에 없는 아이디라서" 막히는 것과 헷갈리지 않도록,
  -- 실재하는 선수를 대상으로 status·user_id 조건만 남겨 검증한다.
  -- rank 는 아래 admin 수동 교정 단언(rank=2)과 겹치지 않게 뒤쪽 번호를 쓴다
  -- (org_code, division_code, rank) 가 유니크다.
  ('gj', 'gj_m_gold', 92, '박실재', 'real-2', '어등산/', 2000, 2000,
   'https://gjtennis.kr/sub4_5.php?member_kind=골드부'),
  ('gj', 'gj_m_gold', 93, '최실재', 'real-3', '어등산/', 1900, 1900,
   'https://gjtennis.kr/sub4_5.php?member_kind=골드부');

-- 확정 연결 1건을 미리 넣어 anon 노출 검사의 대조군으로 쓴다
insert into auth.users (id, email)
values ('99999999-9999-9999-9999-999999999999', 'seed@test.local')
on conflict do nothing;
-- auth.users 트리거가 public.users 행을 이미 만들 수 있으므로 upsert 로 채운다(010 관례).
insert into public.users (id, email, name)
values ('99999999-9999-9999-9999-999999999999', 'seed@test.local', '시드')
on conflict (id) do update set name = excluded.name;
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'seedplayer', '99999999-9999-9999-9999-999999999999', 'confirmed');

-- anon 은 두 테이블 다 못 읽는다.
--   org_player_links 를 빠뜨리면 status='confirmed' 조건만으로 통과하는 구멍이 생긴다.
set local role anon;
select is(
  (select count(*)::int from public.org_rankings),
  0, 'anon 은 org_rankings 를 볼 수 없다');
select is(
  (select count(*)::int from public.org_player_links where status = 'confirmed'),
  0, 'anon 은 확정된 계정 연결을 볼 수 없다');
reset role;

-- 로그인 유저는 확정 연결을 볼 수 있어야 한다(랭킹 화면 배지용) — 위 단언이
-- "아무도 못 읽음"으로 과하게 잠긴 게 아님을 확인하는 긍정 대조.
set local role authenticated;
set local request.jwt.claims to '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}';
select is(
  (select count(*)::int from public.org_player_links where status = 'confirmed'),
  1, '로그인 유저는 확정 연결을 볼 수 있다');
reset role;
reset request.jwt.claims;

-- 유저가 남의 클레임을 confirmed 로 만들 수 없다
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local')
on conflict do nothing;
insert into public.users (id, email, name) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', '김평화'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local', '남의계정')
on conflict (id) do update set name = excluded.name;

-- 신청 자격은 "내가 등록한 협회·부서"다(org_player_links_claim). 아래 pending
-- 클레임이 통과하려면 이 유저에게 gj/gj_m_gold 등록이 있어야 한다.
insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
values ('11111111-1111-1111-1111-111111111111', 'gj', 'default',
        array['gj_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

set local role authenticated;
set local request.jwt.claims to '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- 본인 pending 클레임은 만들 수 있다
select lives_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'vudghk2116', '11111111-1111-1111-1111-111111111111', 'pending')$$,
  '본인 pending 클레임 생성 가능');

-- 스스로 confirmed 로 넣는 것은 막혀야 한다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'real-2', '11111111-1111-1111-1111-111111111111', 'confirmed')$$,
  '42501', null, '유저가 스스로 confirmed 로 넣을 수 없다');

-- 남의 이름으로 클레임하는 것도 막혀야 한다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'real-3', '22222222-2222-2222-2222-222222222222', 'pending')$$,
  '42501', null, '남의 user_id 로 클레임할 수 없다');

reset role;
reset request.jwt.claims;

-- admin 쓰기 경로가 실제로 살아 있는지 확인한다. 이 레포엔 별도 admin Postgres role 이
-- 없다 — 세션 role 은 authenticated 그대로고 is_admin() 이 RLS 안에서 판정한다. grant 에
-- update/insert 가 없으면 아래 두 동작이 RLS 이전 grant 단계에서 죽는다(코덱스 리뷰로
-- 실측된 회귀 — Task 5 승인 큐가 통째로 막히는 지점).
insert into auth.users (id, email) values
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local')
on conflict do nothing;
insert into public.users (id, email, name, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local', '관리자', 'admin')
on conflict (id) do update set role = excluded.role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

-- admin 은 경합 클레임(vudghk2116, 위에서 pending 으로 생성됨)을 confirmed 로 승인할 수 있다
select lives_ok(
  $$update public.org_player_links
    set status = 'confirmed', decided_at = now(),
        decided_by = '33333333-3333-3333-3333-333333333333'
    where org_code = 'gj' and org_player_id = 'vudghk2116' and status = 'pending'$$,
  'admin 은 경합 클레임을 confirmed 로 승인할 수 있다');

-- admin 은 org_rankings 에 수동 교정 행을 넣을 수 있다
select lives_ok(
  $$insert into public.org_rankings
      (org_code, division_code, rank, player_name, org_player_id, club_raw,
       rank_points, total_points, source_url)
    values ('gj', 'gj_m_gold', 2, '관리자입력', 'adminplayer', '테스트클럽/',
            100, 100, 'https://example.test')$$,
  'admin 은 org_rankings 에 수동 교정 행을 넣을 수 있다');

reset role;
reset request.jwt.claims;

-- confirmed 는 협회 선수당 1명만.
--   111 은 위 admin 승인 테스트에서 이미 gj 에 confirmed 행이 하나 있어(org_code, user_id)
--   유니크에 걸리므로 여기서는 아직 gj 에 confirmed 가 없는 222/444 를 쓴다 — 그래야
--   이 단언이 노리는 (org_code, org_player_id) 유니크(같은 협회 선수 중복)만 걸린다.
insert into auth.users (id, email) values
  ('44444444-4444-4444-4444-444444444444', 'd@test.local')
on conflict do nothing;
insert into public.users (id, email, name) values
  ('44444444-4444-4444-4444-444444444444', 'd@test.local', 'dupe유저')
on conflict (id) do update set name = excluded.name;

insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'dupe', '22222222-2222-2222-2222-222222222222', 'confirmed');
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'dupe', '44444444-4444-4444-4444-444444444444', 'confirmed')$$,
  '23505', null, '같은 협회 선수에 confirmed 가 둘일 수 없다');

select * from finish();
rollback;
