create extension if not exists pgtap with schema extensions;

begin;
select plan(5);

-- 실제 만료 판정 로직은 TypeScript 쪽(tournament_status.ts)에 있고
-- supabase/functions/tests/tournament_status_sync_test.ts 에서 검증한다.
-- 여기서는 그 로직이 의존하는 스키마(컬럼)가 실제로 존재하는지만 확인한다.

select has_column('public', 'tournaments', 'last_seen_at',
  '크롤러가 목록에서 마지막으로 본 시각 컬럼이 있다');
select has_column('public', 'tournaments', 'delisted_at',
  '목록이탈로 auto-close 된 시각 컬럼이 있다(날짜-close 와 구분용)');
select has_column('public', 'crawl_sources', 'last_listing_parsed_at',
  '소스가 마지막으로 전체 목록을 훑은 시각 컬럼이 있다');

select col_type_is('public', 'tournaments', 'last_seen_at', 'timestamp with time zone',
  'last_seen_at 은 timestamptz');
select col_type_is('public', 'tournaments', 'delisted_at', 'timestamp with time zone',
  'delisted_at 은 timestamptz');

select * from finish();
rollback;
