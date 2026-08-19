create extension if not exists pgtap with schema extensions;

begin;

select plan(3);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'tennis' and published
  ),
  33,
  '테니스 룰북은 기존 검수된 랭킹 규정 33건만 노출한다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'tennis'
      and title like '2026%'
      and body like '%www.itftennis.com/%'
      and published
  ),
  0,
  '준모 검수 전인 ITF 2026 요약은 노출하지 않는다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'tennis'
      and title like '2026%'
      and body like '%www.itftennis.com/%'
      and not published
  ),
  18,
  '추후 검수할 수 있도록 ITF 2026 요약 18건은 비게시 상태로 보존한다'
);

select * from finish();

rollback;
