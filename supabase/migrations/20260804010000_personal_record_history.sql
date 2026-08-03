-- 개인 기록장 1단계 — 개인 전적 + 순위 스냅샷
--
-- 설계: docs/superpowers/specs/2026-08-03-personal-record-history-design.md
--
-- 두 테이블이 서로 다른 것을 담는다.
--   org_player_results : 협회 개인 이력 페이지에서 온 대회별 성적. 과거 포함.
--                        여기 'result'는 그 대회 진출 라운드(1=우승, 4=4강)이지
--                        부서 내 랭킹 순위가 아니다.
--   org_ranking_snapshots : 부서 내 순위·누적 포인트의 시간 축. 지금부터 쌓인다.
--                        실명을 담지 않는다 — org_player_id 만.

begin;

-- ═══════════════════════════════════════════════
-- 1) 개인 대회 전적
-- ═══════════════════════════════════════════════
create table public.org_player_results (
  id              uuid primary key default uuid_generate_v7(),
  org_code        text not null,
  org_player_id   text not null,
  tournament_name text not null,
  played_on       date not null,
  event_raw       text,
  -- 협회 표기 원문. '1'·'4'·'16' 과 '16강'·'4강' 이 한 컬럼에 섞여 온다.
  -- 정규화에 실패해도 원문은 남긴다 — 나중에 소급 정규화할 수 있게.
  result_raw      text not null,
  -- 진출 라운드 정규화값(1=우승, 2=준우승, 4=4강 …). 못 읽으면 NULL.
  -- 추측값이나 0으로 채우지 않는다.
  result_round    int,
  -- 협회 표의 포인트 칸은 항상 숫자이고 빈칸이 관측된 적이 없다. result_round 와
  -- 달리 "못 읽음" 자체가 관측되지 않으므로 0 을 기본값으로 둬도 추측값을 채우는
  -- 게 아니다 — 실제 0점이거나 파싱이 확정적으로 성공한 값만 들어온다.
  points          int not null default 0,
  fetched_at      timestamptz not null default now(),
  unique (org_code, org_player_id, tournament_name, played_on)
);

-- 화면이 항상 "내 것 전부를 최신순"으로 읽는다.
create index org_player_results_player_idx
  on public.org_player_results (org_code, org_player_id, played_on desc);

alter table public.org_player_results enable row level security;

-- TO authenticated 를 명시한다. 생략하면 PUBLIC 이 되어 anon 조회가
-- is_admin() 권한 오류(42501)로 죽는다 — #365 에서 33개 테이블이 이 함정에 걸렸다.
create policy org_player_results_own_select on public.org_player_results
  for select to authenticated
  using (exists (
    select 1 from public.org_player_links l
     where l.org_code = org_player_results.org_code
       and l.org_player_id = org_player_results.org_player_id
       and l.user_id = (select auth.uid())
       and l.status = 'confirmed'
  ));

-- 쓰기는 service_role 전용(rolbypassrls)이라 admin 쓰기 정책을 두지 않는다.
-- authenticated 에 select 만 grant 돼 있어(아래) for all 정책은 INSERT/UPDATE/
-- DELETE 를 grant 단계에서 막힌 죽은 정책이 된다 — for select 로 좁힌다.
create policy org_player_results_admin_all on public.org_player_results
  for select to authenticated
  using (is_admin());

-- 쓰기는 크롤러(service_role) 전용. service_role 은 rolbypassrls 라 정책이 없어도 통과한다.

-- ═══════════════════════════════════════════════
-- 2) 순위 스냅샷
-- ═══════════════════════════════════════════════
create table public.org_ranking_snapshots (
  id            uuid primary key default uuid_generate_v7(),
  org_code      text not null,
  division_code text not null,
  org_player_id text not null,
  captured_on   date not null,
  rank          int not null,
  total_points  int not null,
  -- 제약에 이름을 준다. 자동 생성 이름은 길이 제한에 잘려 예측이 안 되고,
  -- 검증 단계에서 이 제약을 떼었다 붙였다 해야 한다.
  constraint org_ranking_snapshots_daily_key
    unique (org_code, division_code, org_player_id, captured_on)
);

create index org_ranking_snapshots_player_idx
  on public.org_ranking_snapshots (org_code, org_player_id, captured_on);

alter table public.org_ranking_snapshots enable row level security;

create policy org_ranking_snapshots_own_select on public.org_ranking_snapshots
  for select to authenticated
  using (exists (
    select 1 from public.org_player_links l
     where l.org_code = org_ranking_snapshots.org_code
       and l.org_player_id = org_ranking_snapshots.org_player_id
       and l.user_id = (select auth.uid())
       and l.status = 'confirmed'
  ));

-- 쓰기는 service_role 전용(rolbypassrls)이라 admin 쓰기 정책을 두지 않는다.
create policy org_ranking_snapshots_admin_all on public.org_ranking_snapshots
  for select to authenticated
  using (is_admin());

-- 클라이언트 롤 테이블 권한 — 이 레포 모델은 "권한은 넓게 + 행 통제는 RLS".
-- 권한이 없으면 RLS 이전에 permission denied 로 죽는다(011_api_role_grants).
grant select on public.org_player_results, public.org_ranking_snapshots
  to anon, authenticated;
grant all on public.org_player_results, public.org_ranking_snapshots
  to service_role;

-- ═══════════════════════════════════════════════
-- 3) 스냅샷 적재 — 기존 교체 RPC 안에서 같은 트랜잭션으로
-- ═══════════════════════════════════════════════
-- 별도 호출 지점을 만들지 않는 이유:
--   · 부서 교체 직후라 모든 스냅샷 행이 방금 크롤한 값이다
--   · 0행 가드로 건너뛴 부서는 RPC 자체가 안 불려 낡은 값이 오늘 날짜로 안 박힌다
--   · 교체가 롤백되면 스냅샷도 롤백된다
create or replace function public.replace_org_ranking_division(
  p_org        text,
  p_division   text,
  p_source_url text,
  p_rows       jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted int;
begin
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    raise exception 'replace_org_ranking_division: 빈 목록으로 % / % 를 교체할 수 없다',
      p_org, p_division;
  end if;

  delete from public.org_rankings
  where org_code = p_org and division_code = p_division;

  insert into public.org_rankings
    (org_code, division_code, rank, player_name, org_player_id,
     club_raw, rank_points, total_points, source_url)
  select
    p_org, p_division,
    (r ->> 'rank')::int,
    r ->> 'player_name',
    r ->> 'org_player_id',
    r ->> 'club_raw',
    (r ->> 'rank_points')::int,
    (r ->> 'total_points')::int,
    p_source_url
  from jsonb_array_elements(p_rows) as r;

  -- row_count 는 직전 문장 것이다. 아래 스냅샷 insert 보다 반드시 먼저 읽는다.
  get diagnostics v_inserted = row_count;

  -- 하루 1행. on conflict do nothing 이라 그날 첫 크롤 값이 남는다(덮지 않는다).
  insert into public.org_ranking_snapshots
    (org_code, division_code, org_player_id, captured_on, rank, total_points)
  select r.org_code, r.division_code, r.org_player_id,
         current_date, r.rank, r.total_points
    from public.org_rankings r
   where r.org_code = p_org and r.division_code = p_division
     and r.org_player_id is not null
  on conflict do nothing;

  return v_inserted;
end;
$$;

comment on function public.replace_org_ranking_division is
  '한 협회·부서의 랭킹 미러를 한 트랜잭션으로 교체하고 그날치 스냅샷을 남긴다. service_role 전용(크롤러).';

-- create or replace 는 기존 ACL 을 유지하지만, 20260803060000 이 회수한 상태가
-- 유지되는지는 020_ranking_rpc_grants 가 지킨다. 여기서 다시 명시해 의도를 남긴다.
revoke execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  to service_role;

-- ═══════════════════════════════════════════════
-- 4) 개인 전적 적재 RPC — 크롤러 전용
-- ═══════════════════════════════════════════════
create or replace function public.upsert_org_player_results(
  p_org           text,
  p_org_player_id text,
  p_rows          jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if p_rows is null or jsonb_array_length(p_rows) = 0 then
    return 0;  -- 전적이 없는 선수는 정상이다. 예외로 만들지 않는다.
  end if;

  insert into public.org_player_results
    (org_code, org_player_id, tournament_name, played_on,
     event_raw, result_raw, result_round, points, fetched_at)
  select
    p_org, p_org_player_id,
    r ->> 'tournament_name',
    (r ->> 'played_on')::date,
    r ->> 'event_raw',
    r ->> 'result_raw',
    nullif(r ->> 'result_round', '')::int,
    coalesce((r ->> 'points')::int, 0),
    now()
  from jsonb_array_elements(p_rows) as r
  on conflict (org_code, org_player_id, tournament_name, played_on)
  do update set
    event_raw    = excluded.event_raw,
    result_raw   = excluded.result_raw,
    result_round = excluded.result_round,
    points       = excluded.points,
    fetched_at   = excluded.fetched_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.upsert_org_player_results is
  '연결 승인자 1명의 협회 대회 전적을 적재한다. 협회가 성적을 정정할 수 있어 갱신한다. service_role 전용(크롤러).';

revoke execute on function
  public.upsert_org_player_results(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.upsert_org_player_results(text, text, jsonb)
  to service_role;

commit;
