-- match_entries 자기신고 경로가 점수를 스스로 못 쓰는지 검증한다.
-- 배경: 랭킹 점수의 원천은 서버가 검증한 결과만 쓴다(20260724040000 마이그레이션).
--       유저가 points_earned 를 직접 쓸 수 있으면 랭킹이 성립하지 않는다.
-- 페르소나 시드에 의존하지 않도록 픽스처를 이 파일 안에서 만든다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

-- 픽스처: 일반 회원(관리자 아님) + 자격 충족(만 14세 이상 + 휴대폰 인증) + 대회 1건
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('00000000-0000-4000-8000-000000000901',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'rls-match-points@allround.invalid', '', now(), now(), now());

-- auth.users 트리거가 public.users 행을 이미 만들 수 있으므로 upsert 로 채운다.
insert into public.users (id, email, name, role, birth_date)
values ('00000000-0000-4000-8000-000000000901', 'rls-match-points@allround.invalid',
        'RLS 점수 테스트', 'user', '1990-01-01')
on conflict (id) do update
  set name = excluded.name,
      role = 'user',
      birth_date = excluded.birth_date;

-- 자격 게이트(feature/phone-otp-verification)가 머지된 뒤에는 restrictive 정책
-- match_entries_requires_eligible_ins 가 먼저 막아서 [3]번이 실패한다.
-- 컬럼이 있을 때만 휴대폰 인증을 채워, 머지 전/후 양쪽에서 같은 것을 검증한다.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'phone_verified_at'
  ) then
    update public.users set phone_verified_at = now()
    where id = '00000000-0000-4000-8000-000000000901';
  end if;
end $$;

insert into public.tournaments (id, sport, title, start_date, application_deadline,
                                region, region_code, eligible_grades, source, status)
values ('00000000-0000-4000-8000-000000000902', 'tennis', 'RLS 점수 테스트 대회',
        current_date + 14, current_date + 7, '광주', 'gwangju',
        array['gj_m_general'], 'rls-test', 'draft');

-- 검증된 결과 행(admin 이 넣은 점수 있는 행). superuser 로 삽입해 RLS 우회 =
-- service_role/관리자 검증 경로를 흉내낸다. 이 행을 유저가 self 로 지우거나 고칠 수
-- 있으면 안 된다(패배·저평가 기록 세탁 방지).
insert into public.match_entries (id, user_id, tournament_id, division,
                                  points_earned, source, final_round)
values ('00000000-0000-4000-8000-000000000903',
        '00000000-0000-4000-8000-000000000901',
        '00000000-0000-4000-8000-000000000902', 'gj_m_gold', 120, 'admin', 'winner');

-- 로컬 클린 재생 시 DML grant 가 누락되면 RLS 가 아닌 권한오류로 오탐된다.
grant all on public.match_entries to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000901","role":"authenticated"}',
  true
);

select throws_ok(
  $$insert into public.match_entries (user_id, tournament_id, division, points_earned)
    values ('00000000-0000-4000-8000-000000000901',
            '00000000-0000-4000-8000-000000000902', 'gj_m_general', 99999)$$,
  '42501',
  null,
  '자기신고로 points_earned 를 채워 넣을 수 없다'
);

select throws_ok(
  $$insert into public.match_entries (user_id, tournament_id, division, source)
    values ('00000000-0000-4000-8000-000000000901',
            '00000000-0000-4000-8000-000000000902', 'gj_m_general', 'crawl')$$,
  '42501',
  null,
  '자기신고를 크롤 출처로 위조할 수 없다'
);

select lives_ok(
  $$insert into public.match_entries (user_id, tournament_id, division, final_round)
    values ('00000000-0000-4000-8000-000000000901',
            '00000000-0000-4000-8000-000000000902', 'gj_m_general', 'winner')$$,
  '점수 없는 정상 이력 등록은 그대로 된다'
);

select throws_ok(
  $$insert into public.match_entries (user_id, tournament_id, division)
    values ('00000000-0000-4000-8000-000000000901',
            '00000000-0000-4000-8000-000000000902', 'gj_m_general')$$,
  '23505',
  null,
  '같은 대회·부서를 두 번 등록할 수 없다'
);

-- ── 검증된 행 보호 (codex GATE FAIL 재현) ──
-- RLS 위반 DELETE/UPDATE 는 예외를 던지지 않고 0건 처리된다. 그래서 throws_ok 가 아니라
-- "행이 그대로 남았는지"로 검증한다.

select lives_ok(
  $$delete from public.match_entries
    where id = '00000000-0000-4000-8000-000000000903'$$,
  'self 가 검증된 행 DELETE 를 시도해도 예외 없이 0건 처리'
);
select is(
  (select count(*)::int from public.match_entries
     where id = '00000000-0000-4000-8000-000000000903'),
  1,
  '검증된 행은 self DELETE 로 지워지지 않는다 (기록 세탁 차단)'
);

select lives_ok(
  $$update public.match_entries set points_earned = 1, final_round = 'runner_up'
    where id = '00000000-0000-4000-8000-000000000903'$$,
  'self 가 검증된 행 UPDATE 를 시도해도 예외 없이 0건 처리'
);
select is(
  (select points_earned from public.match_entries
     where id = '00000000-0000-4000-8000-000000000903'),
  120,
  '검증된 행의 점수는 self UPDATE 로 바뀌지 않는다'
);

-- 본인 자기신고 행은 스스로 관리(삭제)할 수 있어야 한다 (긍정 대조)
select lives_ok(
  $$delete from public.match_entries
    where user_id = '00000000-0000-4000-8000-000000000901'
      and division = 'gj_m_general' and source = 'manual'$$,
  '본인 자기신고 행은 스스로 삭제할 수 있다'
);
select is(
  (select count(*)::int from public.match_entries
     where user_id = '00000000-0000-4000-8000-000000000901' and division = 'gj_m_general'),
  0,
  '자기신고 행은 실제로 삭제된다'
);

select * from finish();
rollback;
