create extension if not exists pgtap with schema extensions;

begin;

select plan(3);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '풋살 경기장 크기'
      and body like '%25~42m%'
      and body like '%16~25m%'
      and body like '%38~42m%'
      and body like '%20~25m%'
      and published
  ),
  '일반·국제 풋살 경기장 크기를 실제 수치로 안내한다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '풋살 경기장 크기'
      and body like '%너비: 3m%'
      and body like '%높이: 2m%'
      and published
  ),
  '풋살 골대 규격을 함께 안내한다'
);

select ok(
  not exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '규칙 1 – 피치 (경기장)'
      and published
  ),
  '추상적인 기존 피치 제목은 노출하지 않는다'
);

select * from finish();

rollback;
