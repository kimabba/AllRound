create extension if not exists pgtap with schema extensions;

begin;

select plan(3);

select ok(
  (
    select count(*) >= 5
    from public.rule_articles
    where sport = 'tennis'
      and published
      and title not like '2026%'
  ),
  '기존에 게시하던 테니스 규정은 그대로 유지한다'
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
