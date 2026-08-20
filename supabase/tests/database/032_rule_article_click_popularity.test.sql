create extension if not exists pgtap with schema extensions;

begin;
select plan(12);

select has_table('public', 'rule_article_clicks', '룰 클릭 테이블이 존재한다');
select has_function(
  'public',
  'record_rule_article_click',
  array['uuid'],
  '룰 클릭 기록 함수가 존재한다'
);
select has_function(
  'public',
  'popular_rule_highlight_24h',
  array['sport'],
  '최근 24시간 인기 룰 함수가 존재한다'
);
select is(
  has_function_privilege('anon', 'public.record_rule_article_click(uuid)', 'EXECUTE'),
  false,
  '비로그인 사용자는 룰 클릭을 기록할 수 없다'
);
select is(
  has_function_privilege('authenticated', 'public.record_rule_article_click(uuid)', 'EXECUTE'),
  true,
  '로그인 사용자는 룰 클릭을 기록할 수 있다'
);
select is(
  has_table_privilege('authenticated', 'public.rule_article_clicks', 'INSERT'),
  false,
  '로그인 사용자는 클릭 테이블에 직접 삽입할 수 없다'
);

insert into auth.users (id, email) values
  ('77777777-7777-4777-8777-777777777771', 'rule-click-1@test.local'),
  ('77777777-7777-4777-8777-777777777772', 'rule-click-2@test.local')
on conflict do nothing;

insert into public.users (id, email, name) values
  ('77777777-7777-4777-8777-777777777771', 'rule-click-1@test.local', '룰클릭1'),
  ('77777777-7777-4777-8777-777777777772', 'rule-click-2@test.local', '룰클릭2')
on conflict (id) do update set name = excluded.name;

insert into public.rule_articles
  (id, sport, category, title, body, order_idx, published)
values
  ('88888888-8888-4888-8888-888888888881', 'futsal', '테스트 파울', '테스트 누적 파울', '본문', 991, true),
  ('88888888-8888-4888-8888-888888888882', 'futsal', '테스트 골키퍼', '테스트 4초 제한', '본문', 992, true)
on conflict (id) do update set published = true;

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"77777777-7777-4777-8777-777777777771","role":"authenticated"}';

select is(
  public.record_rule_article_click('88888888-8888-4888-8888-888888888881'),
  true,
  '첫 클릭은 기록한다'
);
select is(
  public.record_rule_article_click('88888888-8888-4888-8888-888888888881'),
  false,
  '같은 사용자의 24시간 내 반복 클릭은 기록하지 않는다'
);
select is(
  (select count(*)::int from public.rule_article_clicks),
  0,
  '일반 사용자는 클릭 원본 행을 직접 조회할 수 없다'
);

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"77777777-7777-4777-8777-777777777772","role":"authenticated"}';

select is(
  public.record_rule_article_click('88888888-8888-4888-8888-888888888881'),
  true,
  '다른 사용자의 클릭은 별도로 기록한다'
);

reset role;
reset request.jwt.claims;

select is(
  (select article_click_count::int
     from public.popular_rule_highlight_24h('futsal')
    where article_id = '88888888-8888-4888-8888-888888888881'),
  2,
  '최근 24시간 유효 클릭 두 건을 합산한다'
);
select is(
  (select category from public.popular_rule_highlight_24h('futsal')),
  '테스트 파울',
  '클릭 합계가 가장 높은 카테고리를 반환한다'
);

select * from finish();
rollback;
