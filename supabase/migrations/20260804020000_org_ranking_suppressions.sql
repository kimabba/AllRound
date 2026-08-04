-- 랭킹 미러 억제 목록 — 삭제 요청을 영구적으로 만든다
--
-- 문제: org_rankings 는 크롤마다 replace_org_ranking_division() 이 부서 단위로
--   delete + insert 한다. 삭제 요청을 받아 행을 지워도, 협회가 계속 공표하면
--   **다음 크롤이 그대로 되살린다.** 요청자에게 "처리했습니다"라고 회신한 뒤
--   하루 만에 다시 나타난다 — 개인정보보호법 §36(정정·삭제) 대응이 실질적으로 무효다.
--   (docs/team/RUNBOOK-org-ranking-deletion-request.md 가 이 한계를 기록해뒀고,
--    "첫 요청이 들어오면 바로 만들어야 한다"고 적어뒀다. 앱이 출시돼 랭킹 화면과
--    연락처가 사용자에게 노출된 지금이 그 시점이다.)
--
-- 해법: 억제 목록을 두고 크롤이 insert 할 때 걸러낸다. 지운 사람은 다시 안 들어온다.
--
-- 매칭 키가 둘인 이유: 협회 HTML 에서 org_player_id 를 못 뽑는 행이 있다
--   (파서가 성명 셀의 player_rank('아이디') 에서 추출하는데, 그 링크가 없는 행이 있다).
--   아이디가 있으면 그걸로 정확히 특정하고, 없으면 성명 + 소속 원문으로 맞춘다.
--
-- 이 테이블 자체가 개인정보다(삭제를 요청한 사람의 성명·소속). 클라이언트에 열지 않는다.

begin;

create table public.org_ranking_suppressions (
  id            uuid primary key default uuid_generate_v7(),
  org_code      text not null,
  -- 둘 중 하나는 반드시 있어야 한다(아래 check).
  org_player_id text,
  player_name   text,
  club_raw      text,
  -- 접수 기록. 언제 무슨 근거로 지웠는지 남겨야 나중에 설명할 수 있다.
  requested_at  timestamptz not null default now(),
  note          text,
  constraint org_ranking_suppressions_key_present
    check (org_player_id is not null or player_name is not null)
);

comment on table public.org_ranking_suppressions is
  '협회 랭킹 미러에서 제외할 대상. 크롤이 insert 시 걸러내 삭제 요청이 재크롤로 되살아나지 않게 한다. 개인정보보호법 §36 대응.';

-- 크롤 RPC 가 부서 교체마다 이 테이블을 org_code 로 훑는다.
create index org_ranking_suppressions_org_idx
  on public.org_ranking_suppressions (org_code);

alter table public.org_ranking_suppressions enable row level security;

-- 관리자만 읽는다. 쓰기는 service_role(운영자가 SQL 로 접수 처리).
-- TO authenticated 를 명시한다 — 생략하면 PUBLIC 이 되어 비로그인 조회가
-- is_admin() 권한 오류(42501)로 죽는다(#365).
create policy org_ranking_suppressions_admin_select
  on public.org_ranking_suppressions
  for select to authenticated
  using (is_admin());

-- 테이블 권한은 넓게, 행 통제는 RLS 가 전담한다(011_api_role_grants 의 모델).
-- 정책이 없는 anon 은 에러가 아니라 0행을 본다.
grant select on public.org_ranking_suppressions to anon, authenticated;
grant all on public.org_ranking_suppressions to service_role;

-- ═══════════════════════════════════════════════
-- 크롤 RPC 가 억제 대상을 걸러내게 한다
-- ═══════════════════════════════════════════════
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
  from jsonb_array_elements(p_rows) as r
  -- 억제 대상 제외. **두 경로 중 하나라도 맞으면** 제외한다.
  --
  -- 왜 "둘 중 하나"인가: 파서가 협회 HTML 에서 org_player_id 를 **매번 뽑는다는
  -- 보장이 없다**(성명 셀의 player_rank('아이디') 링크가 없는 행이 있어 fallback 을 탄다).
  -- 아이디로만 매칭하면, 억제해 둔 사람이 다음 크롤에 아이디 없이(null) 들어올 때
  -- `'abc' = null` 이 NULL 이 되어 매칭이 빗나가고 **그대로 되살아난다.**
  -- 그래서 억제 행에 아이디와 성명+소속을 **둘 다** 기록하고, 어느 쪽으로든 걸리게 한다.
  --
  -- 소속은 협회 표기가 비어 있거나 후행 슬래시가 붙어 coalesce 로 맞춘다.
  -- 주의: 성명+소속 경로는 **같은 이름 + 같은 소속인 동명이인을 구분하지 못한다.**
  -- 그 경우는 아이디로만 특정할 수 있다(런북 참조).
  where not exists (
    select 1
      from public.org_ranking_suppressions s
     where s.org_code = p_org
       and (
         (s.org_player_id is not null
            and s.org_player_id = (r ->> 'org_player_id'))
         or (s.player_name is not null
            and s.player_name = (r ->> 'player_name')
            and coalesce(s.club_raw, '') = coalesce(r ->> 'club_raw', ''))
       )
  );

  -- row_count 는 직전 문장 것이다. 아래 스냅샷 insert 보다 반드시 먼저 읽는다.
  -- 억제로 걸러진 행은 여기 안 잡힌다 — 실제로 저장된 수가 맞다.
  get diagnostics v_inserted = row_count;

  -- 하루 1행. on conflict do nothing 이라 그날 첫 크롤 값이 남는다(덮지 않는다).
  -- org_rankings 에서 뽑으므로 억제 대상은 애초에 여기 들어오지 않는다.
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
  '한 협회·부서의 랭킹 미러를 한 트랜잭션으로 교체하고 그날치 스냅샷을 남긴다. org_ranking_suppressions 대상은 제외한다. service_role 전용(크롤러).';

revoke execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  to service_role;

commit;
