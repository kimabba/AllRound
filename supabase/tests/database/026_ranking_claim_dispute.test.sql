create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

select has_column('public', 'org_player_links', 'note', '사유 메모 컬럼이 있다');

-- ── 시드 ────────────────────────────────────────────────────────────
-- 경합하는 두 사람은 이름이 반드시 같다 — 정책이 users.name = player_name 을
-- 요구하기 때문이다. 이의신청이 필요한 이유가 여기에 있다.
insert into auth.users (id, email) values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'first@test.local'),
  ('aaaaaaa1-0000-0000-0000-000000000002', 'second@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'first@test.local', '김평화'),
  ('aaaaaaa1-0000-0000-0000-000000000002', 'second@test.local', '김평화')
on conflict (id) do update set name = excluded.name;

insert into public.user_tennis_orgs (user_id, org, division, division_codes, is_primary) values
  ('aaaaaaa1-0000-0000-0000-000000000001', 'gj', 'default', array['gj_m_gold'], true),
  ('aaaaaaa1-0000-0000-0000-000000000002', 'gj', 'default', array['gj_m_gold'], true)
on conflict (user_id, org, division) do update set
  division_codes = excluded.division_codes;

insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 1, '김평화', 'vudghk2116', '어등산/', 2649, 2649, 'https://x');

-- 먼저 들어온 사람이 확정을 가져간 상태를 만든다.
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'vudghk2116', 'aaaaaaa1-0000-0000-0000-000000000001', 'confirmed');

-- ── 이의신청: 남이 확정한 선수에도 pending 을 걸 수 있어야 한다 ────────
-- 이 경로가 막혀 있으면 이의신청 화면을 붙여도 서버가 거부한다.
set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaa1-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status, note)
    values ('gj', 'vudghk2116', 'aaaaaaa1-0000-0000-0000-000000000002', 'pending',
            '어등산클럽 소속입니다. 010-0000-0000')$$,
  '남이 확정한 선수에도 이의신청(pending)을 걸 수 있다');

-- 사유는 공백·탭·줄바꿈만으로 채울 수 없다.
select throws_ok(
  $$insert into public.org_player_links (org_code, org_player_id, user_id, status, note)
    values ('gj', 'vudghk2116', 'aaaaaaa1-0000-0000-0000-000000000002', 'pending',
            E'  \t\n ')$$,
  '23514', null, '공백·탭·줄바꿈만 적은 사유는 거부된다');

-- 상한 300자.
select throws_ok(
  format(
    $$insert into public.org_player_links (org_code, org_player_id, user_id, status, note)
      values ('gj', 'vudghk2116', 'aaaaaaa1-0000-0000-0000-000000000002', 'pending', %L)$$,
    repeat('가', 301)),
  '23514', null, '301자 사유는 거부된다');

-- 상한은 저장되는 원문 길이로 잰다. btrim 결과만 재면 앞에 공백을 잔뜩 붙여
-- 얼마든지 긴 값을 밀어넣을 수 있다(codex 리뷰 2026-08-18).
select throws_ok(
  format(
    $$insert into public.org_player_links (org_code, org_player_id, user_id, status, note)
      values ('gj', 'vudghk2116', 'aaaaaaa1-0000-0000-0000-000000000002', 'pending', %L)$$,
    repeat(' ', 5000) || '짧은사유'),
  '23514', null, '앞뒤 공백으로 부풀린 긴 사유도 거부된다');

reset role;
reset request.jwt.claims;

select is(
  (select note from public.org_player_links
   where org_player_id = 'vudghk2116'
     and user_id = 'aaaaaaa1-0000-0000-0000-000000000002'),
  '어등산클럽 소속입니다. 010-0000-0000',
  'pending 인 동안 사유가 남아 있다');

-- ── 확정을 두 명이 동시에 가질 수 없다 ───────────────────────────────
-- 관리자가 기존 연결을 먼저 풀지 않고 승인하면 여기서 막힌다.
select throws_ok(
  $$update public.org_player_links set status = 'confirmed'
    where org_player_id = 'vudghk2116'
      and user_id = 'aaaaaaa1-0000-0000-0000-000000000002'$$,
  '23505', null, '기존 확정을 풀지 않으면 승인이 막힌다');

-- ── 결정되는 순간 사유가 사라진다 ────────────────────────────────────
-- confirmed 행은 org_player_links_read 로 전체 공개된다. 사유에 연락처가
-- 들어가므로 공개 대상이 되기 전에 비워야 한다.
update public.org_player_links set status = 'rejected'
where org_player_id = 'vudghk2116'
  and user_id = 'aaaaaaa1-0000-0000-0000-000000000002';

select is(
  (select note from public.org_player_links
   where org_player_id = 'vudghk2116'
     and user_id = 'aaaaaaa1-0000-0000-0000-000000000002'),
  null, '반려되면 사유가 지워진다');

-- 기존 확정을 풀고 승인하는 정상 경로.
update public.org_player_links set status = 'rejected'
where org_player_id = 'vudghk2116'
  and user_id = 'aaaaaaa1-0000-0000-0000-000000000001';

update public.org_player_links set status = 'pending', note = '연락처 010-1111-2222'
where org_player_id = 'vudghk2116'
  and user_id = 'aaaaaaa1-0000-0000-0000-000000000002';

update public.org_player_links set status = 'confirmed'
where org_player_id = 'vudghk2116'
  and user_id = 'aaaaaaa1-0000-0000-0000-000000000002';

select is(
  (select status from public.org_player_links
   where org_player_id = 'vudghk2116'
     and user_id = 'aaaaaaa1-0000-0000-0000-000000000002'),
  'confirmed', '기존 확정을 풀면 이의신청자를 승인할 수 있다');

select is(
  (select note from public.org_player_links
   where org_player_id = 'vudghk2116'
     and user_id = 'aaaaaaa1-0000-0000-0000-000000000002'),
  null, '승인되면 사유가 지워진다(확정 행은 전체 공개다)');

select * from finish();
rollback;
