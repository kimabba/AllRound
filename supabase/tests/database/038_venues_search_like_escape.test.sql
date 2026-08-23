-- 구장 검색은 검색어에 LIKE 메타문자(%, _)가 들어와도 리터럴로 취급해야 한다.
-- 대회검색(037_tournament_search_ignore_whitespace)과 같은 취지, venues_search 전용.

create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

insert into public.venues
  (id, sport, name, region, address, venue_type)
values
  ('e1000000-0000-0000-0000-000000000001', 'tennis', '검색기호 100% 구장',
   '광주광역시', '광주 서구', 'outdoor'),
  ('e1000000-0000-0000-0000-000000000002', 'tennis', '검색기호 A_B 구장',
   '서울특별시', '서울 강남구', 'indoor'),
  ('e1000000-0000-0000-0000-000000000003', 'tennis', '평범한 구장',
   '부산광역시', '부산 해운대구', 'outdoor')
on conflict (id) do nothing;

select is(
  (select array_agg(id order by id)
     from public.venues_search(p_query => '100%', p_limit => 500)
    where id between 'e1000000-0000-0000-0000-000000000001'
                 and 'e1000000-0000-0000-0000-000000000003'),
  array['e1000000-0000-0000-0000-000000000001'::uuid],
  '%를 문자 그대로 취급해 이름에 100%가 있는 구장만 찾는다'
);

select is(
  (select array_agg(id order by id)
     from public.venues_search(p_query => 'A_B', p_limit => 500)
    where id between 'e1000000-0000-0000-0000-000000000001'
                 and 'e1000000-0000-0000-0000-000000000003'),
  array['e1000000-0000-0000-0000-000000000002'::uuid],
  '_를 문자 그대로 취급해 이름에 A_B가 있는 구장만 찾는다(단일문자 와일드카드 아님)'
);

select is(
  (select count(*)::int
     from public.venues_search(p_query => '%', p_limit => 500)
    where id between 'e1000000-0000-0000-0000-000000000001'
                 and 'e1000000-0000-0000-0000-000000000003'),
  1,
  '검색어가 % 한 글자여도 전체 구장이 아니라 %가 이름에 있는 구장만 나온다'
);

select * from finish();
rollback;
