-- 개인 이력 크롤 대상을 confirmed 연결자에서 전 선수로 확장하기 위한 상태 테이블.
--
-- 설계: docs/superpowers/specs/2026-08-20-org-player-history-full-coverage-design.md
--
-- "마지막으로 개인 이력 크롤을 성공시켰을 때의 포인트"를 저장해, 다음 회차에
-- org_rankings.total_points 와 비교해 바뀐 선수만 다시 긁는다. 어제-오늘 스냅샷
-- diff 방식은 회차를 건너뛰면 추적이 끊기므로 쓰지 않는다(§3.1).

begin;

create table public.org_player_history_crawl_state (
  org_code        text not null,
  org_player_id   text not null,
  last_points     int not null,
  last_crawled_at timestamptz not null default now(),
  primary key (org_code, org_player_id)
);

comment on table public.org_player_history_crawl_state is
  '개인 이력 크롤러 전용 내부 상태. 마지막으로 이력 크롤을 성공시켰을 때의 total_points 를 기록해 변경분만 다시 크롤하는 데 쓴다. 클라이언트는 읽지 않는다.';

alter table public.org_player_history_crawl_state enable row level security;

-- 클라이언트가 읽을 이유가 없는 순수 내부 테이블이지만, 신규 테이블은 RLS
-- enable + 정책이 필수다(AGENTS.md). crawl_audit(007) 과 같은 관례 —
-- admin 조회만 열어 디버깅 때 확인할 길은 남긴다.
create policy org_player_history_crawl_state_admin_only
  on public.org_player_history_crawl_state
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- authenticated 에 SELECT grant 가 반드시 있어야 한다 — 011_api_role_grants.test.sql
-- assertion 1이 "authenticated 가 SELECT 못 하는 public 테이블이 없다"를 강제한다.
-- 실제 접근 통제는 위 RLS 정책(admin만)이 한다 — "권한은 넓게 + RLS 가 행 통제"
-- 모델(011_api_role_grants 관례)이라 grant 를 넓혀도 새 구멍은 없다.
grant select on public.org_player_history_crawl_state to anon, authenticated;
-- 쓰기는 크롤러(service_role) 전용. service_role 은 rolbypassrls 라 RLS 는
-- 통과하지만 테이블 권한(GRANT)은 별도라 명시해야 한다(011_api_role_grants 관례).
grant select, insert, update on public.org_player_history_crawl_state to service_role;

-- ═══════════════════════════════════════════════
-- 상태 기록 RPC — 크롤러 전용
-- ═══════════════════════════════════════════════
create or replace function public.record_org_player_history_crawl_state(
  p_org           text,
  p_org_player_id text,
  p_points        int
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.org_player_history_crawl_state
    (org_code, org_player_id, last_points, last_crawled_at)
  values (p_org, p_org_player_id, p_points, now())
  on conflict (org_code, org_player_id) do update
    set last_points = excluded.last_points,
        last_crawled_at = excluded.last_crawled_at;
$$;

comment on function public.record_org_player_history_crawl_state is
  '개인 이력 크롤이 성공한 직후 그 선수의 마지막 크롤 시점 포인트를 기록한다. service_role 전용(크롤러).';

revoke execute on function
  public.record_org_player_history_crawl_state(text, text, int)
  from public, anon, authenticated;
grant execute on function
  public.record_org_player_history_crawl_state(text, text, int)
  to service_role;

commit;
