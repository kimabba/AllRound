create extension if not exists pgtap with schema extensions;

begin;
select plan(19);

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
delete from public.tournaments where id in ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000009');

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
  ('a0000000-0000-0000-0000-000000000003', 'tennis', '가을 대회 C', '광주',
   current_date + 40, current_date + 41, 'published'),
  -- 진행 중(오늘 이전 시작, 아직 안 끝남) 대회 D 와, D 마지막 날에 시작하는 대회 E.
  -- D 의 UUID 가 더 작아 self-join 에서 항상 t1 이 된다 — 날짜 조건을 t1 한쪽에만
  -- 걸던 시절엔 이 쌍이 통째로 사라졌다.
  ('a0000000-0000-0000-0000-000000000004', 'tennis', '진행 중 대회 D', '광주',
   current_date - 3, current_date + 2, 'published'),
  ('a0000000-0000-0000-0000-000000000005', 'tennis', '겹침 대회 E', '광주',
   current_date + 2, current_date + 4, 'published'),
  -- 겹침 시작(= 늦게 시작하는 쪽)이 90일 밖인 쌍 G-H. least() 기준이던 시절엔
  -- G(d+80) 가 90일 안이라는 이유로 이 쌍이 통과했다 — conflict_date 기준이면 제외.
  ('a0000000-0000-0000-0000-000000000007', 'tennis', '먼 미래 대회 G', '광주',
   current_date + 80, current_date + 100, 'published'),
  ('a0000000-0000-0000-0000-000000000008', 'tennis', '먼 미래 대회 H', '광주',
   current_date + 95, current_date + 96, 'published'),
  -- 장기 대회 L(d+14~d+50). C(d+40~41) 와 겹치고, d+45 모임과도 겹친다.
  -- 옛 정렬(a_start)이면 L 쪽 행이 시작일 d+14 로 당겨져 C-L(d+40)보다 앞에 왔다 —
  -- conflict_date 정렬이면 C-L(d+40) → L-모임(d+45) 순서.
  ('a0000000-0000-0000-0000-000000000009', 'tennis', '장기 대회 L', '광주',
   current_date + 14, current_date + 50, 'published')
on conflict (id) do nothing;

-- 본인 제보 draft 대회 F — RLS(submitted_by 본인)로는 보이지만 확정 대회가 아니다.
-- A/B 와 겹치고 d+10 모임도 기간 안 — status 필터가 없으면 결과에 섞여 나온다.
insert into public.tournaments
  (id, sport, title, region, start_date, end_date, status, submitted_by)
values
  ('a0000000-0000-0000-0000-000000000006', 'tennis', '내 제보 draft 대회 F', '광주',
   current_date + 10, current_date + 11, 'draft', '55555555-5555-5555-5555-555555555555')
on conflict (id) do nothing;

insert into public.tournament_favorites (user_id, tournament_id) values
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000001'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000002'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000003'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000004'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000005'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000006'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000007'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000008'),
  ('55555555-5555-5555-5555-555555555555', 'a0000000-0000-0000-0000-000000000009')
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
   '정기 모임', (current_date + 10)::timestamptz + interval '10 hour'),
  -- 진행 중 대회 D 기간 안(E 기간 밖)의 모임.
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '진행 중 모임', (current_date + 1)::timestamptz + interval '10 hour'),
  -- 장기 대회 L 기간 안(다른 대회 기간 밖)의 모임 — 정렬 검증용.
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '가을 모임', (current_date + 45)::timestamptz + interval '10 hour'),
  -- 진행 중 대회 D(d-3~d+2) 기간 안이지만 이미 지난(d-1) 모임 — 과거 모임 제외 검증용.
  ('b0000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '지난 모임', (current_date - 1)::timestamptz + interval '10 hour')
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
  6, '대회-대회 겹침 3건 + 대회-모임 겹침 3건 = 총 6건(draft F 와 90일 밖 G-H 는 제외)');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_tournament'),
  3, '대회끼리 겹침은 3건(A-B, D-E, C-L)');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_club_event'),
  3, '대회-모임 겹침은 3건(대회 A, 진행 중 대회 D, 장기 대회 L)');

-- 본인 제보 draft(F)는 RLS 로는 보이지만(submitted_by 본인) 겹침 결과에는 안 나온다.
-- A/B/모임과 실제로 겹치므로 status 필터가 없으면 여기서 잡힌다.
select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where a_id = 'a0000000-0000-0000-0000-000000000006'
       or b_id = 'a0000000-0000-0000-0000-000000000006'),
  0, '본인 제보 draft 대회는 published/closed 필터로 겹침 결과에서 제외된다');

-- 겹침 시작일(늦게 시작하는 H, d+95)이 90일 밖인 쌍 — least() 기준이던 시절엔
-- G(d+80) 덕에 통과했다. conflict_date 기준이면 제외.
select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where a_id in ('a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000008')
       or b_id in ('a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000008')),
  0, '겹침 시작일이 90일 밖이면 이른 쪽 대회가 90일 안이어도 제외된다');

-- 정렬은 conflict_date(겹침이 실제 일어나는 날) 기준. 옛 정렬(a_start)이면
-- L-모임 행이 L 시작일 d+14 로 당겨져 A 행들 바로 뒤, C-L(d+40) 앞에 왔다.
select results_eq(
  $q$ select a_title || ' | ' || b_title from public.my_schedule_conflicts() $q$,
  array[
    '진행 중 대회 D | 진행 중 모임',
    '진행 중 대회 D | 겹침 대회 E',
    '겹침 대회 A | 정기 모임',
    '겹침 대회 A | 겹침 대회 B',
    '가을 대회 C | 장기 대회 L',
    '장기 대회 L | 가을 모임'
  ]::text[],
  '결과가 conflict_date 오름차순 — 장기 대회의 시작일이 아니라 겹침 날짜로 정렬된다');

-- 진행 중(오늘 이전 시작) 대회가 조용히 빠지지 않는지 — 날짜 조건을 self-join 한쪽에만
-- 걸면 UUID 가 작은 D 가 t1 이 되어 이 두 건이 통째로 사라진다.
select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_tournament'
      and a_id = 'a0000000-0000-0000-0000-000000000004'
      and b_id = 'a0000000-0000-0000-0000-000000000005'),
  1, '오늘 이전에 시작해 아직 안 끝난 대회 D 도 대회 E 와의 겹침으로 잡힌다');

select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where kind = 'tournament_vs_club_event'
      and a_id = 'a0000000-0000-0000-0000-000000000004'),
  1, '진행 중 대회 D 기간의 클럽 모임도 겹침으로 잡힌다');

-- 진행 중 대회 D 기간 안이라도 이미 지난 모임은 살아있는 겹침이 아니다 —
-- 과거 모임 하한이 없으면 '지난 모임'(d-1)이 D 와의 겹침으로 잡힌다.
select is(
  (select count(*)::int from public.my_schedule_conflicts()
    where b_title = '지난 모임'),
  0, '진행 중 대회 기간 안이라도 이미 지난 클럽 모임은 겹침 결과에서 제외된다');

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
