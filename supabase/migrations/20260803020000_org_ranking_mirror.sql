-- 협회 랭킹 미러 + 선수↔계정 연결
--
-- 설계: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md
--
-- 왜 테이블이 둘인가: org_rankings 는 크롤마다 부서 단위로 갈아엎는다(협회가 시즌·공표일을
--   안 주므로 "현재 상태"만 유지). 힘들게 확인한 계정 연결이 그때마다 날아가면 안 되므로
--   org_player_links 를 분리한다.
--
-- 앱은 점수를 계산하지 않는다. 협회 공표값을 그대로 옮긴다.

begin;

-- ═══════════════════════════════════════════════
-- org_rankings — 협회 공표 순위표 미러 (현재상태)
-- ═══════════════════════════════════════════════
create table public.org_rankings (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  division_code text not null references public.tennis_divisions(code),
  rank          int  not null check (rank > 0),
  player_name   text not null,
  -- 협회 시스템 선수 아이디. 랭킹표 HTML 의 player_rank('...') 1번 인자.
  -- null 허용: 링크가 없는 행(사진·이름 셀에 <a> 가 없는 경우) 대비.
  org_player_id text,
  club_raw      text,  -- 소속 원문 그대로('화순/토요피닉스/'). 파싱·정규화 안 함
  rank_points   int  not null check (rank_points  >= 0),  -- 화면의 '순위포인트'
  total_points  int  not null check (total_points >= 0),  -- 화면의 '전체포인트'
  source_url    text not null,
  fetched_at    timestamptz not null default now(),
  unique (org_code, division_code, rank),
  unique (org_code, division_code, org_player_id)
);

comment on table public.org_rankings is
  '협회 공표 랭킹표 미러. 크롤마다 부서 단위 delete+insert. 앱이 계산한 값이 아니다.';
comment on column public.org_rankings.rank_points is
  '협회 화면의 순위포인트. 규정상 total_points 와 다른 집계(베스트25 vs 베스트15)여야 하나 현재 협회 화면은 같은 값이다 — 합치지 말 것.';

create index org_rankings_player_name_idx on public.org_rankings (player_name);
create index org_rankings_org_player_idx  on public.org_rankings (org_code, org_player_id);

alter table public.org_rankings enable row level security;

-- 모든 정책에 to authenticated 를 명시한다.
--   is_admin() 은 anon EXECUTE 가 없어(20260626055521, JY-79), 정책이 PUBLIC 이면
--   플래너가 anon 쿼리에서도 그 조각을 InitPlan 으로 먼저 평가해
--   permission denied for function is_admin (42501) 로 죽는다.
--   TO 절을 붙이면 anon 세션에서 정책 자체가 평가 대상이 아니라 문제가 사라진다.
--   (레포에 같은 결함이 grades·tennis_divisions 에 이미 있다 — 별도 이슈.)

-- 읽기: 로그인 유저만. 이 레포는 anon 에도 테이블 grant 를 주고 행 단위 통제를
--   RLS 에 맡기므로(011_api_role_grants), 이 auth.role() 조건이 비로그인 인터넷에
--   실명 명단이 재공개되는 것을 막는 유일한 방어다.
create policy org_rankings_read on public.org_rankings
  for select to authenticated
  using (auth.role() = 'authenticated');

-- 쓰기: 크롤러는 service_role(RLS 우회), 수동 교정은 admin
create policy org_rankings_admin on public.org_rankings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════
-- org_player_links — 협회 선수 ↔ 앱 계정
-- ═══════════════════════════════════════════════
create table public.org_player_links (
  id            uuid primary key default gen_random_uuid(),
  org_code      text not null references public.tennis_orgs(code),
  org_player_id text not null,
  -- 탈퇴 시 연결 즉시 소멸. 단 org_rankings 의 실명 행은 남는다(협회가 여전히 공표 중).
  user_id       uuid not null references public.users(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending','confirmed','rejected')),
  claimed_at    timestamptz not null default now(),
  decided_at    timestamptz,
  decided_by    uuid references public.users(id),
  unique (org_code, org_player_id, user_id)
);

comment on table public.org_player_links is
  '협회 선수 ↔ 앱 계정 연결. 크롤과 독립적으로 생존한다(미러는 갈아엎어도 링크는 산다).';

-- confirmed 는 1:1 강제. pending 은 여럿 허용 — 경합 클레임을 관리자가 보고 고른다.
create unique index org_player_links_confirmed_player_key
  on public.org_player_links (org_code, org_player_id) where status = 'confirmed';
create unique index org_player_links_confirmed_user_key
  on public.org_player_links (org_code, user_id) where status = 'confirmed';

alter table public.org_player_links enable row level security;

create policy org_player_links_claim on public.org_player_links
  for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');

-- 읽기: 본인 것 전부 + 타인 것은 confirmed 만(랭킹 화면의 "앱 유저" 배지용).
--   anon 차단은 to authenticated 가 담당한다(위 grant 섹션 참고). auth.role() 조건은
--   defense-in-depth — 없으면 TO 절이 실수로 빠졌을 때 status='confirmed' 만으로 통과해
--   확정 연결 전체(user_id·org_player_id·decided_by)를 읽힌다. org_player_id 는
--   org_rankings 를 통해 실명과 이어지므로 org_rankings_read 와 같은 이유로 막는다.
create policy org_player_links_read on public.org_player_links
  for select to authenticated
  using (
    auth.role() = 'authenticated'
    and (user_id = (select auth.uid()) or status = 'confirmed')
  );

create policy org_player_links_withdraw on public.org_player_links
  for delete to authenticated
  using (user_id = (select auth.uid()) and status = 'pending');

create policy org_player_links_admin on public.org_player_links
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ═══════════════════════════════════════════════
-- grant — 클린 재생 시 누락 이력이 있어 명시한다(011_api_role_grants).
--   이 레포는 anon 을 포함해 테이블 권한을 주고 행 단위 통제를 RLS 가 전담한다.
--   실제 anon 차단은 각 정책의 to authenticated 절이 담당한다(anon 세션에는 정책
--   자체가 적용 대상이 아니라 무조건 0행). USING 절의 auth.role() 조건은 그 위에 얹은
--   defense-in-depth — TO 절이 실수로 빠지는 경우에도 anon 을 한 번 더 막는다.
-- ═══════════════════════════════════════════════
grant select on public.org_rankings to anon, authenticated;
grant all    on public.org_rankings to service_role;
grant select, insert, delete on public.org_player_links to anon, authenticated;
grant all    on public.org_player_links to service_role;

-- ═══════════════════════════════════════════════
-- 죽은 컬럼 정리 — user_tennis_orgs.ranking_points
--   056 에서 추가만 되고 채우는 경로도 읽는 경로도 없다(프로덕션 전 행 null, 2026-08-03 실측).
--   이름이 org_rankings 의 rank_points/total_points 와 겹쳐, 나중에 누가 여기에 자기신고 값을
--   넣으면 20260724040000 에서 match_entries 를 잠근 이유가 그대로 무너진다. Commander 지시로 제거.
-- ═══════════════════════════════════════════════
alter table public.user_tennis_orgs drop column if exists ranking_points;

commit;
