create extension if not exists pgtap with schema extensions;

begin;
select plan(12);

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
    values ('gj', 'zzz', '11111111-1111-1111-1111-111111111111', 'confirmed')$$,
  '42501', null, '유저가 스스로 confirmed 로 넣을 수 없다');

-- 남의 이름으로 클레임하는 것도 막혀야 한다
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'yyy', '22222222-2222-2222-2222-222222222222', 'pending')$$,
  '42501', null, '남의 user_id 로 클레임할 수 없다');

reset role;
reset request.jwt.claims;

-- confirmed 는 협회 선수당 1명만
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'dupe', '11111111-1111-1111-1111-111111111111', 'confirmed');
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status)
    values ('gj', 'dupe', '22222222-2222-2222-2222-222222222222', 'confirmed')$$,
  '23505', null, '같은 협회 선수에 confirmed 가 둘일 수 없다');

select * from finish();
rollback;
