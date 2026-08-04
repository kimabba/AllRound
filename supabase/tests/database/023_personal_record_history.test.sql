-- 개인 기록장 — 테이블 격리와 스냅샷 적재 (#JY 개인기록장 1단계)
--
-- 지키는 것:
--   1) 내 전적만 보인다 (남의 org_player_id 행은 안 보인다) — org_player_results, org_ranking_snapshots 둘 다
--   2) anon 조회가 에러가 아니라 0행이다 (#365 함정) — 실제로 행이 존재하는 상태에서 검증
--   3) replace_org_ranking_division 의 반환값이 "스냅샷 필터링 전" 랭킹 삽입 행수다
--      (get diagnostics 가 스냅샷 insert 보다 먼저여야 하는 설계를 반환값으로 가드)
--   4) 랭킹 교체가 스냅샷을 남기고, 같은 날 두 번 돌아도 행이 안 는다
--   5) upsert_org_player_results 가 갱신(중복 안 늘어남)·NULL 보존·빈 배열을 올바르게 다룬다

create extension if not exists pgtap with schema extensions;

begin;
select plan(17);

-- ── 픽스처: 두 사용자, 각자 다른 협회 선수에 연결 ────────────────
set local role postgres;

insert into public.org_player_links (org_code, org_player_id, user_id, status)
values ('gj', 'zz_mine',   '00000000-0000-4000-8000-000000000002', 'confirmed'),
       ('gj', 'zz_theirs', '00000000-0000-4000-8000-000000000003', 'confirmed');

-- org_rankings.division_code 는 tennis_divisions(code) FK 다. 실제 카탈로그를
-- 오염시키지 않도록 격리용 부서를 하나 임시로 넣는다(트랜잭션 롤백으로 사라진다).
insert into public.tennis_divisions (code, org_code, label_ko)
values ('zz_div', 'gj', 'zz 테스트 부서');

insert into public.org_player_results
  (org_code, org_player_id, tournament_name, played_on, event_raw, result_raw, result_round, points)
values ('gj', 'zz_mine',   'zz 내 대회',   '2026-05-01', '골드부', '1',    1,    1000),
       ('gj', 'zz_mine',   'zz 내 대회2',  '2026-06-01', '골드부', '16강', 16,   60),
       ('gj', 'zz_theirs', 'zz 남의 대회', '2026-05-01', '골드부', '1',    1,    1000);

-- ═══════════════════════════════════════════════
-- 1) 랭킹 교체 → 스냅샷 적재 (postgres 로 미리 실행 — 이후 RLS 검증의 전제 데이터)
--    `perform` 은 plpgsql 전용이라 .sql 파일에서 쓰면 문법 오류다. 평범한 select 로 부른다.
--    3행 중 1행은 org_player_id 가 NULL 이다 — 랭킹 삽입 행수(3)와 스냅샷 필터링 후
--    행수(2, org_player_id not null 만)를 다르게 만들어 반환값으로 순서 가드를 세운다.
-- ═══════════════════════════════════════════════
select is(
  public.replace_org_ranking_division(
    'gj', 'zz_div', 'https://example.test/zz',
    '[{"rank":1,"player_name":"zz선수","org_player_id":"zz_mine",
       "club_raw":null,"rank_points":100,"total_points":100},
      {"rank":2,"player_name":"zz경쟁자","org_player_id":"zz_theirs",
       "club_raw":null,"rank_points":90,"total_points":90},
      {"rank":3,"player_name":"zz무명","org_player_id":null,
       "club_raw":null,"rank_points":10,"total_points":10}]'::jsonb
  ),
  3,
  '반환값은 스냅샷 필터링 전 랭킹 삽입 행수(3)다 — get diagnostics 가 스냅샷 insert 보다 먼저 읽혀야 한다'
);

select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  2,
  '부서 교체가 오늘자 스냅샷 2행을 남긴다(org_player_id 있는 행만)'
);

-- ═══════════════════════════════════════════════
-- 2) 내 것만 보인다 — org_player_results, org_ranking_snapshots 둘 다
-- ═══════════════════════════════════════════════
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}';

select is(
  (select count(*)::int from public.org_player_results),
  2,
  '연결 승인된 본인 전적 2건만 보인다'
);
select is(
  (select count(*)::int from public.org_player_results where org_player_id = 'zz_theirs'),
  0,
  '남의 org_player_id 전적은 보이지 않는다'
);

select is(
  (select count(*)::int from public.org_ranking_snapshots),
  1,
  '본인(zz_mine) 스냅샷만 보인다'
);
select is(
  (select count(*)::int from public.org_ranking_snapshots where org_player_id = 'zz_theirs'),
  0,
  '남의 스냅샷(zz_theirs)은 보이지 않는다'
);

-- ═══════════════════════════════════════════════
-- 3) anon 은 에러가 아니라 0행이다 — 이 시점엔 두 테이블 다 실제 행이 있다
-- ═══════════════════════════════════════════════
reset role;
set local role anon;
select is(
  (select count(*)::int from public.org_player_results),
  0,
  'anon 은 전적을 0행으로 본다 (42501 로 죽지 않는다, 행이 실제로 있어도)'
);
select is(
  (select count(*)::int from public.org_ranking_snapshots),
  0,
  'anon 은 스냅샷을 0행으로 본다 (42501 로 죽지 않는다, 행이 실제로 있어도)'
);

-- ═══════════════════════════════════════════════
-- 4) 같은 날 두 번 돌아도 스냅샷이 안 는다
-- ═══════════════════════════════════════════════
reset role;
set local role postgres;
select public.replace_org_ranking_division(
  'gj', 'zz_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz선수","org_player_id":"zz_mine",
     "club_raw":null,"rank_points":95,"total_points":95},
    {"rank":2,"player_name":"zz경쟁자","org_player_id":"zz_theirs",
     "club_raw":null,"rank_points":80,"total_points":80},
    {"rank":3,"player_name":"zz무명","org_player_id":null,
     "club_raw":null,"rank_points":5,"total_points":5}]'::jsonb
);
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_div' and captured_on = current_date),
  2,
  '같은 날 재크롤해도 스냅샷 행이 늘지 않는다'
);

-- ═══════════════════════════════════════════════
-- 5) upsert_org_player_results — Task 2·3 이 그대로 올라타는 RPC
-- ═══════════════════════════════════════════════
select is(
  public.upsert_org_player_results(
    'gj', 'zz_upsert',
    '[{"tournament_name":"zz 업서트 대회","played_on":"2026-07-01",
       "event_raw":"골드부","result_raw":"8강","result_round":8,"points":50}]'::jsonb
  ),
  1,
  'upsert 최초 적재는 1행을 반환한다'
);
select is(
  public.upsert_org_player_results(
    'gj', 'zz_upsert',
    '[{"tournament_name":"zz 업서트 대회","played_on":"2026-07-01",
       "event_raw":"골드부","result_raw":"공동4강","result_round":null,"points":99}]'::jsonb
  ),
  1,
  'upsert 재적재도 1행을 반환한다(갱신이지 삽입이 아니다)'
);
select is(
  (select count(*)::int from public.org_player_results where org_player_id = 'zz_upsert'),
  1,
  '같은 (org, player, tournament_name, played_on) 재적재는 행을 늘리지 않는다'
);
select is(
  (select points from public.org_player_results where org_player_id = 'zz_upsert'),
  99,
  '재적재 시 points 가 갱신된다'
);
-- ok(... is null) 은 행이 아예 없어도 참이 된다(공허하게 통과). 행 존재와
-- NULL 값을 한 단언으로 묶어 앞 단언이 실패해도 여기서 공허 통과하지 않게 한다.
select is(
  (select count(*)::int from public.org_player_results
    where org_player_id = 'zz_upsert' and result_round is null),
  1,
  'result_round 가 없는 값은 NULL 로 들어간다(0 으로 추측해 채우지 않는다) — 행 존재까지 확인'
);
select is(
  public.upsert_org_player_results('gj', 'zz_upsert_empty', '[]'::jsonb),
  0,
  '빈 배열은 예외 없이 0 을 반환한다(전적 없는 선수는 정상)'
);

-- points 가 빈 문자열로 와도(협회 표에서 관측된 적은 없지만) 캐스팅 전에 nullif 로
-- 막아야 한다 — coalesce((r->>'points')::int, 0) 순서면 ''::int 캐스팅에서 예외가
-- 나서 upsert 전체가 롤백된다. lives_ok 로 예외 없이 끝나는지부터 확인한다.
select lives_ok(
  $$select public.upsert_org_player_results(
    'gj', 'zz_upsert_blank_points',
    '[{"tournament_name":"zz 포인트빈값","played_on":"2026-07-02",
       "event_raw":null,"result_raw":"8강","result_round":8,"points":""}]'::jsonb
  )$$,
  '포인트 칸이 빈 문자열이어도 예외 없이 처리된다(캐스팅 전에 nullif 로 방어)'
);
select is(
  (select points from public.org_player_results where org_player_id = 'zz_upsert_blank_points'),
  0,
  '빈 문자열 포인트는 0 으로 들어간다(추측값이 아니라 명시적 기본값)'
);

select * from finish();
rollback;
