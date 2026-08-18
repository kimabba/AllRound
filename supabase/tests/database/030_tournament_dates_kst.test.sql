-- 대회 날짜 판정이 KST 인지 (20260819030000_tournament_dates_use_kst.sql).
--
-- 이 DB 의 TimeZone 은 UTC 다. `current_date` 를 쓰면 한국 시각 00:00~09:00 동안
-- 하루 이른 날짜로 판정해, 그 시간대에만 어제 끝난 대회가 '다가오는 대회'로
-- 정렬되고 어제 마감된 대회가 '접수 중'으로 보인다.
--
-- 시각 의존 함정: 아래 시드는 전부 `(now() AT TIME ZONE 'Asia/Seoul')::date` 기준
-- 상대 날짜라 언제 돌려도 같은 결과가 나온다. 다만 그 표현식은 함수가 쓰는 것과
-- 같으므로, 둘 다 UTC 기준으로 되돌아가면 낮 시간대엔 이 동작 테스트가 통과해
-- 버린다 — 그래서 prosrc 정적 검사를 함께 둔다. 회귀를 실제로 잡는 건 그쪽이다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

-- ── 회귀 방지: 두 함수에 current_date 가 남아 있으면 안 된다 ──────────
-- 대소문자(CURRENT_DATE)와 now()::date 까지 함께 막는다. 둘 다 문법상 유효하고
-- current_date 와 똑같이 UTC 를 따라가므로, 한 철자만 막으면 회귀가 그대로 통과한다.
select is(
  (select bool_or(p.prosrc ~* 'current_date|now\(\)::date')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'tournament_search_by_slots'),
  false, 'tournament_search_by_slots 는 UTC 기준 오늘(current_date·now()::date) 을 쓰지 않는다');

select is(
  (select bool_or(p.prosrc ~* 'current_date|now\(\)::date')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'tournaments_for_user'),
  false, 'tournaments_for_user 는 UTC 기준 오늘(current_date·now()::date) 을 쓰지 않는다');

-- 079 사고(인자 수가 달라져 replace 대신 새 오버로드 생성 → 42725) 재발 방지.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'tournament_search_by_slots'),
  1, 'tournament_search_by_slots 오버로드는 하나뿐이다');

-- ── 시드 ────────────────────────────────────────────────────────
-- KST 오늘을 기준으로 어제 끝난 대회 / 오늘 진행 중인 대회 / 미래 대회.
insert into public.tournaments
  (id, sport, title, region, start_date, end_date, application_deadline, status)
values
  ('d0000000-0000-0000-0000-000000000001', 'tennis', 'KST 어제 끝난 대회', '광주',
   (now() at time zone 'Asia/Seoul')::date - 3,
   (now() at time zone 'Asia/Seoul')::date - 1,
   (now() at time zone 'Asia/Seoul')::date - 1, 'published'),
  ('d0000000-0000-0000-0000-000000000002', 'tennis', 'KST 오늘 진행 중 대회', '광주',
   (now() at time zone 'Asia/Seoul')::date - 1,
   (now() at time zone 'Asia/Seoul')::date,
   (now() at time zone 'Asia/Seoul')::date, 'published'),
  ('d0000000-0000-0000-0000-000000000003', 'tennis', 'KST 미래 대회', '광주',
   (now() at time zone 'Asia/Seoul')::date + 7,
   (now() at time zone 'Asia/Seoul')::date + 8,
   (now() at time zone 'Asia/Seoul')::date + 5, 'published')
on conflict (id) do nothing;

-- ── 정렬: 끝난 대회는 뒤로 ──────────────────────────────────────
-- 기간을 넓게 줘 세 건이 모두 걸리게 한 뒤 순서만 본다("8월 대회 뭐가 있어?" 처럼
-- 기간을 명시하면 지난 대회도 포함하되 아래로 밀어야 한다).
--
-- p_match_count 를 크게 잡는 이유: LIMIT 은 함수 **안**에서 걸리는데 'KST %' 필터는
-- 함수 **밖**이다. 기본 10 으로 두면 시드에 대회가 몇 건만 늘어도 정렬상 맨 뒤인
-- '어제 끝난 대회'부터 잘려 나가, KST 와 무관한 이유로 실패한다.
select is(
  (select array_agg(title order by ord)
     from (
       select title, row_number() over () as ord
         from public.tournament_search_by_slots(
           p_user_id => '55555555-5555-5555-5555-555555555555',
           p_sport => 'tennis',
           p_date_from => (now() at time zone 'Asia/Seoul')::date - 30,
           p_date_to => (now() at time zone 'Asia/Seoul')::date + 30,
           p_only_my_grade => false,
           p_match_count => 500,
           p_include_closed => true)
        where title like 'KST %'
     ) s),
  array['KST 오늘 진행 중 대회', 'KST 미래 대회', 'KST 어제 끝난 대회'],
  '끝난 대회는 맨 뒤 — 오늘 진행 중인 대회는 앞에 남는다');

-- ── 모집 상태: 오늘 마감은 아직 접수 중 ─────────────────────────
select is(
  (select array_agg(title order by title)
     from public.tournament_search_by_slots(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_sport => 'tennis',
       p_date_from => (now() at time zone 'Asia/Seoul')::date - 30,
       p_date_to => (now() at time zone 'Asia/Seoul')::date + 30,
       p_only_my_grade => false,
       p_match_count => 500,
       p_recruiting => 'open',
       p_include_closed => true)
    where title like 'KST %'),
  array['KST 미래 대회', 'KST 오늘 진행 중 대회'],
  'open — 마감일이 KST 오늘이면 아직 접수 중이다');

select is(
  (select array_agg(title order by title)
     from public.tournament_search_by_slots(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_sport => 'tennis',
       p_date_from => (now() at time zone 'Asia/Seoul')::date - 30,
       p_date_to => (now() at time zone 'Asia/Seoul')::date + 30,
       p_only_my_grade => false,
       p_match_count => 500,
       p_recruiting => 'closed',
       p_include_closed => true)
    where title like 'KST %'),
  array['KST 어제 끝난 대회'],
  'closed — KST 어제 마감된 대회만 마감으로 잡힌다');

-- 목록 화면(tournaments_for_user)도 같은 기준인지.
select is(
  (select array_agg(title order by title)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_sport => 'tennis',
       p_only_my_grade => false,
       -- 위와 같은 이유로 LIMIT 을 넉넉히(기본 50).
       p_limit => 500,
       p_recruiting => 'open')
    where title like 'KST %'),
  array['KST 미래 대회', 'KST 오늘 진행 중 대회'],
  '목록 화면도 KST 기준으로 접수 중을 판정한다');

select * from finish();
rollback;
