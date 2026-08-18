create extension if not exists pgtap with schema extensions;

begin;
select plan(9);

-- ── 시드 ────────────────────────────────────────────────────────────
insert into auth.users (id, email) values
  ('bbbbbbb1-0000-0000-0000-00000000000a', 'admin1@test.local'),
  ('bbbbbbb1-0000-0000-0000-00000000000b', 'admin2@test.local'),
  ('bbbbbbb1-0000-0000-0000-000000000001', 'holder@test.local'),
  ('bbbbbbb1-0000-0000-0000-000000000002', 'claimant@test.local')
on conflict do nothing;

insert into public.users (id, email, name, role) values
  ('bbbbbbb1-0000-0000-0000-00000000000a', 'admin1@test.local', '관리자일', 'admin'),
  ('bbbbbbb1-0000-0000-0000-00000000000b', 'admin2@test.local', '관리자이', 'admin'),
  ('bbbbbbb1-0000-0000-0000-000000000001', 'holder@test.local', '김평화', 'user'),
  ('bbbbbbb1-0000-0000-0000-000000000002', 'claimant@test.local', '김평화', 'user')
on conflict (id) do update set name = excluded.name, role = excluded.role;

insert into public.org_rankings
  (org_code, division_code, rank, player_name, org_player_id, club_raw,
   rank_points, total_points, source_url)
values
  ('gj', 'gj_m_gold', 1, '김평화', 'vudghk2116', '어등산/', 2649, 2649, 'https://x');

-- ── 신청 → 관리자 전원에게 ───────────────────────────────────────────
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'vudghk2116', 'bbbbbbb1-0000-0000-0000-000000000001', 'pending');

-- 리터럴로 못 박지 않는다. personas.sql 이 이미 관리자를 넣어 두므로
-- (pgtap-fixtures-come-from-personas) 실제 관리자 수와 대조해야
-- "전원에게 간다"를 검증하는 것이 된다.
select is(
  (select count(*)::int from public.notifications
   where type = 'ranking_claim_request'),
  (select count(*)::int from public.users where role = 'admin'),
  '신청 하나에 관리자 전원이 알림을 받는다');

select is(
  (select title from public.notifications
   where type = 'ranking_claim_request' limit 1),
  '랭킹 본인 연결 신청', '빈 자리 신청은 이의신청이 아니다');

-- pgTAP 의 like 는 SQL 키워드와 겹쳐 못 쓴다(alike 가 대응). ok 로 충분하다.
select ok(
  (select body from public.notifications
   where type = 'ranking_claim_request' limit 1) like '%김평화%',
  '알림 본문에 선수명이 들어간다');

-- ── 승인 → 신청자에게 ────────────────────────────────────────────────
update public.org_player_links set status = 'confirmed'
where org_player_id = 'vudghk2116'
  and user_id = 'bbbbbbb1-0000-0000-0000-000000000001';

select is(
  (select user_id from public.notifications
   where type = 'ranking_claim_approved'),
  'bbbbbbb1-0000-0000-0000-000000000001'::uuid,
  '승인 알림은 신청자에게만 간다');

-- 관리자가 decided_by 만 다시 써도 알림이 또 나가면 안 된다.
update public.org_player_links set decided_at = now()
where org_player_id = 'vudghk2116'
  and user_id = 'bbbbbbb1-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.notifications
   where type = 'ranking_claim_approved'),
  1, '상태가 그대로면 알림이 다시 나가지 않는다');

-- ── 이의신청 → 관리자에게 "이의신청"으로 ─────────────────────────────
insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'vudghk2116', 'bbbbbbb1-0000-0000-0000-000000000002', 'pending');

select is(
  (select count(*)::int from public.notifications
   where type = 'ranking_claim_request' and title = '랭킹 연결 이의신청'),
  (select count(*)::int from public.users where role = 'admin'),
  '이미 주인이 있으면 이의신청으로 알린다(관리자 전원)');

-- ── 연결 해제 → 해제당한 사람에게 ────────────────────────────────────
-- 해제는 confirmed → rejected 다. 통보가 없으면 개인 기록장이 조용히 사라진다.
update public.org_player_links set status = 'rejected'
where org_player_id = 'vudghk2116'
  and user_id = 'bbbbbbb1-0000-0000-0000-000000000001';

select is(
  (select user_id from public.notifications
   where type = 'ranking_claim_rejected'),
  'bbbbbbb1-0000-0000-0000-000000000001'::uuid,
  '연결 해제도 당사자에게 통보된다');

select ok(
  (select body from public.notifications
   where type = 'ranking_claim_rejected') like '%해제%',
  '해제 알림 본문이 결과를 말해 준다');

-- ── 트리거 함수는 클라이언트 롤에서 실행 불가 ────────────────────────
select is(
  (select coalesce(string_agg(format('%s:%s', p.proname, r.who), ', '), '(없음)')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join (values ('anon'),('authenticated')) as r(who)
    where n.nspname = 'public'
      and p.proname in ('notify_ranking_claim_request',
                        'notify_ranking_claim_decision')
      and has_function_privilege(r.who, p.oid, 'EXECUTE')),
  '(없음)', '트리거 함수에 anon/authenticated 실행 권한이 없다');

select * from finish();
rollback;
