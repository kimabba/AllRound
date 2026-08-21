-- 랭킹 선수 이력 온디맨드 캐시
--
-- 지키는 것:
--   1) 현재 랭킹 선수만 이력을 교체할 수 있다.
--   2) 교체는 이전 이력을 남기지 않고 캐시 건수·완전 수집 여부를 함께 갱신한다.
--   3) 캐시 메타데이터는 클라이언트가 직접 볼 수 없다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

set local role postgres;

insert into public.tennis_divisions (code, org_code, label_ko)
values ('zz_history_div', 'gj', 'zz 선수 이력 테스트 부서');

select public.replace_org_ranking_division(
  'gj', 'zz_history_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz이력선수","org_player_id":"zz_history_player",
     "club_raw":"zz클럽/","rank_points":100,"total_points":100}]'::jsonb
);

select is(
  public.replace_org_player_history(
    'gj', 'zz_history_player',
    '[{"tournament_name":"zz 첫 대회","played_on":"2026-01-01",
       "event_raw":"일반부","result_raw":"우승","result_round":1,"points":100},
      {"tournament_name":"zz 둘째 대회","played_on":"2026-02-01",
       "event_raw":"일반부","result_raw":"4강","result_round":4,"points":40}]'::jsonb,
    false
  ),
  2,
  '최초 교체는 저장한 이력 건수를 반환한다'
);

select is(
  (select count(*)::int from public.org_player_results
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  2,
  '선수 이력 2건이 저장된다'
);

select is(
  (select result_count from public.org_player_history_fetches
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  2,
  '캐시 메타데이터에 저장 건수를 기록한다'
);

select is(
  (select is_complete from public.org_player_history_fetches
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  false,
  '페이지 상한에 닿은 수집은 불완전 상태를 보존한다'
);

select is(
  public.replace_org_player_history(
    'gj', 'zz_history_player',
    '[{"tournament_name":"zz 최신 대회","played_on":"2026-03-01",
       "event_raw":"일반부","result_raw":"준우승","result_round":2,"points":80}]'::jsonb,
    true
  ),
  1,
  '재수집은 새 이력 건수를 반환한다'
);

select is(
  (select string_agg(tournament_name, ', ' order by played_on)
     from public.org_player_results
    where org_code = 'gj' and org_player_id = 'zz_history_player'),
  'zz 최신 대회',
  '재수집은 이전 사본을 남기지 않고 전체 교체한다'
);

select throws_ok(
  $$select public.replace_org_player_history(
    'gj', 'zz_not_ranked', '[]'::jsonb, true
  )$$,
  'P0001',
  'replace_org_player_history: 현재 랭킹에 없는 선수입니다',
  '현재 랭킹에 없는 선수의 이력은 저장하지 않는다'
);

reset role;
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}';
select is(
  (select count(*)::int from public.org_player_history_fetches),
  0,
  '로그인 사용자도 캐시 메타데이터를 직접 볼 수 없다'
);

select * from finish();
rollback;
