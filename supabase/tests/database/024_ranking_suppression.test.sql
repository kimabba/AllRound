-- 랭킹 억제 목록 가드
--
-- 지키는 것: 삭제 요청으로 억제 목록에 오른 사람은 **다음 크롤에 되살아나지 않는다.**
-- 이게 깨지면 "처리했습니다"라고 회신한 다음 날 그 사람이 다시 앱에 뜬다
-- (개인정보보호법 §36 대응이 무효가 된다).
--
-- 매칭 경로가 둘이라 둘 다 검증한다:
--   1) org_player_id 가 있는 행 — 아이디로 특정
--   2) 아이디가 없는 행 — 성명 + 소속 원문으로 특정

create extension if not exists pgtap with schema extensions;

begin;
select plan(8);

set local role postgres;

-- 부서 코드는 tennis_divisions FK 를 탄다(023 과 같은 이유로 픽스처 필요).
insert into public.tennis_divisions (code, org_code, label_ko)
values ('zz_sup_div', 'gj', 'zz 억제 테스트 부서')
on conflict (code) do nothing;

-- ── 억제 목록: 아이디 기준 1건 + 성명·소속 기준 1건 ──────────────────
-- 아이디 기준 억제는 성명+소속도 함께 기록한다. 협회가 다음 크롤에 아이디를
-- 안 주면(파서 fallback 실패) 아이디 매칭이 빗나가 되살아나기 때문이다.
insert into public.org_ranking_suppressions (org_code, org_player_id, player_name, club_raw, note)
values ('gj', 'zz_gone_id', 'zz아이디삭제', 'zz다른클럽/', '테스트: 아이디 기준 삭제 요청');

insert into public.org_ranking_suppressions (org_code, player_name, club_raw, note)
values ('gj', 'zz삭제요청자', 'zz클럽/', '테스트: 성명+소속 기준 삭제 요청');

-- ── 크롤이 4명을 가져왔다: 억제 2명 + 정상 2명 ───────────────────────
select public.replace_org_ranking_division(
  'gj', 'zz_sup_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz정상자","org_player_id":"zz_stay_id",
     "club_raw":"zz클럽/","rank_points":100,"total_points":100},
    {"rank":2,"player_name":"zz삭제요청자","org_player_id":null,
     "club_raw":"zz클럽/","rank_points":90,"total_points":90},
    {"rank":3,"player_name":"zz아이디삭제","org_player_id":"zz_gone_id",
     "club_raw":"zz다른클럽/","rank_points":80,"total_points":80},
    {"rank":4,"player_name":"zz삭제요청자","org_player_id":null,
     "club_raw":"zz전혀다른클럽/","rank_points":70,"total_points":70}]'::jsonb
);

-- 1) 억제 대상은 저장되지 않는다 — 아이디 기준
select is(
  (select count(*)::int from public.org_rankings
    where division_code = 'zz_sup_div' and org_player_id = 'zz_gone_id'),
  0,
  '아이디로 억제된 선수는 크롤이 저장하지 않는다'
);

-- 2) 억제 대상은 저장되지 않는다 — 성명 + 소속 기준
select is(
  (select count(*)::int from public.org_rankings
    where division_code = 'zz_sup_div'
      and player_name = 'zz삭제요청자' and club_raw = 'zz클럽/'),
  0,
  '성명+소속으로 억제된 선수는 크롤이 저장하지 않는다'
);

-- 3) 동명이인은 지워지지 않는다 — 소속이 다르면 다른 사람이다
select is(
  (select count(*)::int from public.org_rankings
    where division_code = 'zz_sup_div'
      and player_name = 'zz삭제요청자' and club_raw = 'zz전혀다른클럽/'),
  1,
  '같은 이름이라도 소속이 다르면 억제되지 않는다 (동명이인 보호)'
);

-- 4) 억제 대상이 아닌 사람은 정상 저장된다
select is(
  (select count(*)::int from public.org_rankings
    where division_code = 'zz_sup_div' and org_player_id = 'zz_stay_id'),
  1,
  '억제 대상이 아닌 선수는 그대로 저장된다'
);

-- 5) 반환값은 실제 저장된 수다 (4명 중 2명 억제 → 2)
select is(
  public.replace_org_ranking_division(
    'gj', 'zz_sup_div', 'https://example.test/zz',
    '[{"rank":1,"player_name":"zz정상자","org_player_id":"zz_stay_id",
       "club_raw":"zz클럽/","rank_points":100,"total_points":100},
      {"rank":2,"player_name":"zz아이디삭제","org_player_id":"zz_gone_id",
       "club_raw":"zz다른클럽/","rank_points":80,"total_points":80}]'::jsonb
  ),
  1,
  '반환값은 억제를 제외하고 실제 저장된 행 수다'
);

-- 6) 스냅샷에도 억제 대상이 안 들어간다
--    (org_rankings 에서 뽑으므로 자동이지만, 그 연결이 끊기면 여기서 잡힌다)
select is(
  (select count(*)::int from public.org_ranking_snapshots
    where division_code = 'zz_sup_div' and org_player_id = 'zz_gone_id'),
  0,
  '억제 대상은 순위 스냅샷에도 남지 않는다'
);

-- 7) **아이디로 억제한 사람이 아이디 없이 들어와도 막힌다**
--    협회가 player_rank('아이디') 링크를 안 주면 파서가 org_player_id 를 null 로
--    넣는다. 아이디로만 매칭하면 'zz_gone_id' = null 이 NULL 이라 빗나가 되살아난다.
--    성명+소속 경로가 함께 걸려야 한다.
select public.replace_org_ranking_division(
  'gj', 'zz_sup_div', 'https://example.test/zz',
  '[{"rank":1,"player_name":"zz정상자","org_player_id":"zz_stay_id",
     "club_raw":"zz클럽/","rank_points":100,"total_points":100},
    {"rank":2,"player_name":"zz아이디삭제","org_player_id":null,
     "club_raw":"zz다른클럽/","rank_points":80,"total_points":80}]'::jsonb
);
select is(
  (select count(*)::int from public.org_rankings
    where division_code = 'zz_sup_div' and player_name = 'zz아이디삭제'),
  0,
  '아이디로 억제한 사람은 다음 크롤에 아이디가 빠져 들어와도 막힌다'
);

-- 8) 억제 목록 자체는 클라이언트에 안 보인다 (삭제 요청자의 성명·소속이 들어 있다)
reset role;
set local role anon;
select is(
  (select count(*)::int from public.org_ranking_suppressions),
  0,
  'anon 은 억제 목록을 볼 수 없다 (에러가 아니라 0행)'
);
reset role;

select * from finish();
rollback;
