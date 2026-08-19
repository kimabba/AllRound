create extension if not exists pgtap with schema extensions;

begin;

select plan(7);

with published_count as (
  select count(*)::integer as value
  from public.rule_articles
  where sport = 'futsal' and published
)
select is(
  value,
  30,
  format('풋살 룰북은 경기 관련 게시 글 30건만 노출한다 (실제 %s건)', value)
)
from published_count;

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'futsal'
      and category = '부상/컨디션'
      and published
  ),
  0,
  '부상·컨디션 분류는 노출하지 않는다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '풋살과 축구의 주요 차이'
      and body like '%풋살:%5명%'
      and body like '%축구:%11명%'
      and body like '%킥인%스로인%'
      and published
  ),
  '풋살과 축구를 양쪽 기준으로 비교한다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '풋살 포지션'
      and body like '%골레이로%'
      and body like '%픽소%'
      and body like '%아라%'
      and body like '%피보%'
      and published
  ),
  '풋살 포지션 네 가지를 간결하게 설명한다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'futsal'
      and (title like '%알라%' or body like '%알라%')
  ),
  0,
  '풋살 포지션 표기는 모두 아라로 통일한다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'futsal'
      and published
      and title in (
        '풋살 시작, 당신의 인생을 재발견할 5가지 핵심 포인트!',
        '글로 배우는 풋살 잘하는 방법',
        '풋살 후 근육통 완화 및 빠른 회복 전략',
        '겨울철 풋살을 위한 생존 가이드'
      )
  ),
  0,
  '홍보·훈련·건강 가이드는 게시하지 않는다'
);

select ok(
  (
    select bool_and(embedding is null)
    from public.rule_articles
    where sport = 'futsal'
      and title in ('풋살과 축구의 주요 차이', '풋살 포지션')
  ),
  '수정된 글은 임베딩을 다시 생성하도록 무효화한다'
);

select * from finish();

rollback;
