-- 대회 검색은 검색어/대상 필드의 공백 유무와 무관하게 같은 결과를 반환해야 한다.
-- LIKE 메타문자(%, _)는 계속 리터럴로 취급해야 한다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(6);

insert into public.tournaments
  (id, sport, title, organizer, description, region, location, start_date, status)
values
  ('d1000000-0000-0000-0000-000000000001', 'tennis', '광주 오픈',
   '대한 테니스 협회', '생활 체육 대회', '광주 광역시', '진월 국제 테니스장',
   (now() at time zone 'Asia/Seoul')::date + 30, 'published'),
  ('d1000000-0000-0000-0000-000000000002', 'tennis', '검색기호 100% 대회',
   null, null, '서울', null,
   (now() at time zone 'Asia/Seoul')::date + 31, 'published'),
  ('d1000000-0000-0000-0000-000000000003', 'tennis', '검색기호 A_B 대회',
   null, null, '부산', null,
   (now() at time zone 'Asia/Seoul')::date + 32, 'published')
on conflict (id) do nothing;

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '광주오픈', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000001'::uuid],
  '제목의 공백을 생략해도 대회를 찾는다');

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '대한테니스협회', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000001'::uuid],
  '주최자 검색도 공백 유무가 결과에 영향을 주지 않는다');

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '광주광역시', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000001'::uuid],
  '지역 검색도 공백 유무가 결과에 영향을 주지 않는다');

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '진월국제테니스장', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000001'::uuid],
  '장소 검색도 공백 유무가 결과에 영향을 주지 않는다');

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '%', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000002'::uuid],
  '%는 와일드카드가 아니라 리터럴로 검색한다');

select is(
  (select array_agg(id order by id)
     from public.tournaments_for_user(
       p_user_id => '55555555-5555-5555-5555-555555555555',
       p_only_my_grade => false, p_query => '_', p_limit => 500)
    where id between 'd1000000-0000-0000-0000-000000000001'
                 and 'd1000000-0000-0000-0000-000000000003'),
  array['d1000000-0000-0000-0000-000000000003'::uuid],
  '_는 와일드카드가 아니라 리터럴로 검색한다');

select * from finish();
rollback;
