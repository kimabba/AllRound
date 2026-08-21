create extension if not exists pgtap with schema extensions;

begin;

select plan(10);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'tennis'
      and title like '2026%'
  ),
  18,
  'ITF 2026 테니스 요약 18건이 저장된다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'futsal'
      and title like '현행 규칙%'
      and published
  ),
  4,
  'FIFA 현행 풋살 누락 규칙 4건이 게시된다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'tennis'
      and title like '2026%'
      and body like '%https://www.itftennis.com/%'
  ),
  18,
  '모든 ITF 2026 요약에 공식 출처가 남는다'
);

select is(
  (
    select count(*)::integer
    from public.rule_articles
    where sport = 'futsal'
      and title like '현행 규칙%'
      and body like '%https://digitalhub.fifa.com/%'
  ),
  4,
  '모든 풋살 보강 글에 FIFA 공식 출처가 남는다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'tennis'
      and title = '2026 개정 규칙 18 – 풋폴트'
      and body like '%복식에서는 그 위치가 허용%'
  ),
  'ITF 2026 풋폴트 개정사항을 반영한다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'tennis'
      and title = '2026 개정 규칙 27 – 순서·코트 오류 바로잡기'
      and body like '%폴트는 유지되지 않는%'
  ),
  'ITF 2026 오류 정정 개정사항을 반영한다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '풋살 백패스 규칙'
      and body like '%자기 진영%4초%'
      and body not like '%하프라인을 넘긴 뒤%'
      and embedding is null
  ),
  '골키퍼 4초·재터치 오류를 바로잡고 임베딩을 무효화한다'
);

select ok(
  exists(
    select 1
    from public.rule_articles
    where sport = 'futsal'
      and title = '규칙 12 – 파울과 불법행위'
      and body like '%옐로카드는 경고%'
      and body like '%4초 제한%'
      and body not like '%골키퍼의 6초%'
      and embedding is null
  ),
  '옐로카드와 골키퍼 4초 설명 오류를 바로잡는다'
);

select is(
  (
    select count(*)::integer
    from (
      select sport, title
      from public.rule_articles
      where title like '2026%'
         or title like '현행 규칙%'
      group by sport, title
      having count(*) > 1
    ) as duplicates
  ),
  0,
  '보강 콘텐츠 제목이 종목 안에서 중복되지 않는다'
);

select ok(
  (
    select bool_and(embedding is null)
    from public.rule_articles
    where title like '2026%'
       or title like '현행 규칙%'
  ),
  '새 콘텐츠는 임베딩 생성 대기 상태로 시작한다'
);

select * from finish();

rollback;
