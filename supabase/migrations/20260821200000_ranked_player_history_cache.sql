-- 랭킹 선수 이력 온디맨드 캐시
--
-- 전 선수 수천 명을 매일 순회하지 않는다. 사용자가 랭킹표에서 선수를 열 때만
-- Edge Function 이 협회 공개 이력을 가져오고, 이 테이블의 갱신 시각을 기준으로
-- 24시간 동안 재사용한다. org_player_results 의 기존 본인 전용 RLS 는 넓히지 않는다.
--
-- 이력 저장 자체는 새 RPC 를 만들지 않고 정기 크롤러와 같은
-- upsert_org_player_results(20260804010000)를 그대로 재사용한다 — 별도 경로를
-- 만들면 크롤러가 이미 겪은 "같은 대회명+날짜 중복 → 문장 전체 롤백" 사고를
-- 다시 밟는다(2026-08-19 실측, #468). 이 테이블은 순수하게 "언제 마지막으로
-- 긁었는지"만 기록한다.

begin;

create table public.org_player_history_fetches (
  org_code text not null check (org_code in ('gj', 'jn')),
  org_player_id text not null,
  fetched_at timestamptz not null default now(),
  result_count integer not null default 0 check (result_count >= 0),
  is_complete boolean not null default true,
  primary key (org_code, org_player_id)
);

comment on table public.org_player_history_fetches is
  '랭킹 선수 개인 이력의 온디맨드 수집 시각. 실명·성적은 담지 않는다.';

alter table public.org_player_history_fetches enable row level security;

-- authenticated 에 SELECT 권한은 주되 정책을 만들지 않아 직접 조회 결과는 0행이다.
-- Edge Function 의 service_role 만 RLS 를 우회해 캐시 상태를 읽고 쓴다.
grant select on public.org_player_history_fetches to authenticated, service_role;
grant insert, update, delete on public.org_player_history_fetches to service_role;
revoke all on public.org_player_history_fetches from anon;

commit;
