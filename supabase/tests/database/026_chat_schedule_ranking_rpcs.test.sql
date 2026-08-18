create extension if not exists pgtap with schema extensions;

begin;
select plan(13);

select has_function('public', 'my_schedule_conflicts', 'my_schedule_conflicts 함수 존재');
select has_function('public', 'my_confirmed_ranking', 'my_confirmed_ranking 함수 존재');

-- ── 실행 권한 가드 ──────────────────────────────────────────────
select is(
  has_function_privilege('anon', 'public.my_schedule_conflicts(int)', 'EXECUTE'),
  false, 'anon 은 일정겹침 RPC 를 실행할 수 없다');
select is(
  has_function_privilege('authenticated', 'public.my_schedule_conflicts(int)', 'EXECUTE'),
  true, 'authenticated 는 일정겹침 RPC 를 실행할 수 있다');
select is(
  has_function_privilege('service_role', 'public.my_schedule_conflicts(int)', 'EXECUTE'),
  true, 'service_role 는 일정겹침 RPC 를 실행할 수 있다');
select is(
  has_function_privilege('anon', 'public.my_confirmed_ranking()', 'EXECUTE'),
  false, 'anon 은 랭킹조회 RPC 를 실행할 수 없다');
select is(
  has_function_privilege('authenticated', 'public.my_confirmed_ranking()', 'EXECUTE'),
  true, 'authenticated 는 랭킹조회 RPC 를 실행할 수 있다');
select is(
  has_function_privilege('service_role', 'public.my_confirmed_ranking()', 'EXECUTE'),
  true, 'service_role 는 랭킹조회 RPC 를 실행할 수 있다');

-- ── 시드 ────────────────────────────────────────────────────────
delete from public.club_events where club_id = 'b0000000-0000-0000-0000-000000000001';
delete from public.club_members where club_id = 'b0000000-0000-0000-0000-000000000001';
delete from public.clubs where id = 'b0000000-0000-0000-0000-000000000001';
delete from public.org_player_links where user_id = '55555555-5555-5555-5555-555555555555';
delete from public.tournament_favorites where user_id = '55555555-5555-5555-5555-555555555555';
delete from public.tournaments where id in ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003');

insert into auth.users (id, email) values
  ('55555555-5555-5555-5555-555555555555', 'sched-a@test.local')
on conflict do nothing;
insert into public.users (id, email, name) values
  ('55555555-5555-5555-5555-555555555555', 'sched-a@test.local', '박일정')
on conflict (id) do update set name = excluded.name;

-- 겹치는 대회 2건(같은 유저가 둘 다 즐겨찾기)
insert into public.tournaments
  (id, sport, title, region, start_date, end_date, status)
values
  ('a0000000-0000-0000-0000-000000000001', 'tennis', '겹침 대회 A', '광주',
   current_date + 10, current_date + 12, 'published'),
  ('a0000000-0000-0000-0000-000000000002', 'tennis', '겹침 대회 B', '광주',
   current_date + 11, current_date + 13, 'published'),
  ('a0000000-0000-0000-0000-000000000003', 'tennis', '안 겹치는 대회 C', '광주',
   current_date + 40, current_date + 41, 'published')
on conflict (id) do nothing;

insert into public.tournament_favorites (user_id, tournament_id) values
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000001'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000002'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000003')
on conflict do nothing;

-- 클럽 + 모임(대회 A 기간 중 하루)
insert into public.clubs (id, sport, name, region, status) values
  ('b0000000-0000-0000-0000-000000000001', 'tennis', '겹침 테스트 클럽', '광주', 'approved')
on conflict (id) do nothing;
insert into public.club_members (club_id, user_id, role, status) values
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'member', 'active')
on conflict do nothing;
insert into public.club_events (club_id, created_by, title, starts_at) values
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '정기 모임', (current_date + 10)::timestamptz + interval '10 hour')
on conflict do nothing;

-- 랭킹: confirmed 링크가 있는 협회만 조회되어야 함
insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 3, '박일정', 'sched_player_1', 900, 900, 'https://x')
on conflict do nothing;
insert into public.org_player_links (org_code, org_player_id, user_id, status) values
  ('gj', 'sched_player_1', '55555555-5555-5555-5555-555555555555', 'confirmed')
on conflict do nothing;

-- ── my_schedule_conflicts: 대회끼리 겹침 1건 + 대회-모임 겹침 1건 ──
set local role authenticated;
set local request.jwt.claims to '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated"}';

select is(
  (select count(*)::int from public.my_schedule_conflicts()),
  2, '대회-대회 겹침 1건 + 대회-모임 겹침 1건 = 총 2건');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_tournament'),
  1, '대회끼리 겹침은 1건(A-B, C 는 안 겹침)');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_club_event'),
  1, '대회-모임 겹침은 1건(대회 A 만)');

-- ── my_confirmed_ranking: confirmed 링크된 랭킹만 ──────────────────
select is(
  (select count(*)::int from public.my_confirmed_ranking()),
  1, '본인 인증 연결된 랭킹 1건');
select is(
  (select rank from public.my_confirmed_ranking()),
  3, '반환된 순위가 시드값과 일치');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
