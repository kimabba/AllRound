-- 019_crawl_sources.sql
-- Phase 1: 크롤링 sources 어드민 관리 인프라.
--
-- 목적:
--   - 어드민 UI 에서 크롤 대상 사이트를 등록/수정/삭제하고 enabled 토글.
--   - Phase 2 의 dispatcher Edge Function 이 이 테이블을 순회하여 parser 를 호출.
--
-- 이번 마이그레이션 범위 (Phase 1):
--   - 테이블 / RLS / seed (기존 3개 크롤러와 1:1 매핑).
--   - 본 마이그레이션은 dispatcher 도, pg_cron 도 변경하지 않는다.
--     기존 008_cron.sql 의 스케줄과 crawl-tennis-{gwangju,jeonnam,korea} Edge
--     Function 은 그대로 동작하며, 이 테이블은 아직 dispatch 트리거가 아니다.
--
-- 보안:
--   - admin role 만 SELECT/INSERT/UPDATE/DELETE 가능 (RLS).
--   - service_role 은 향후 dispatcher Edge Function 호출용으로 전체 접근 허용.
--   - 일반 사용자에게는 전혀 노출되지 않음.

-- =========================================================================
-- ENUM: source_type
-- =========================================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'crawl_source_type') then
    create type public.crawl_source_type as enum ('board', 'rss', 'json_api', 'sitemap');
  end if;
end $$;

-- =========================================================================
-- 테이블
-- =========================================================================
create table if not exists public.crawl_sources (
  id uuid primary key default public.uuid_generate_v7(),
  name text not null,                                   -- 사람이 보는 식별자 (예: "광주테니스협회 게시판")
  slug text not null unique,                            -- 코드 식별자 (예: "tennis-gwangju") — dispatcher 가 parser 매핑 키로 사용
  url text not null,                                    -- listing URL
  sport text,                                           -- 'tennis' | 'futsal' | NULL (룰북 등 종목 무관)
  region text,                                          -- 한글 지역 (예: '광주', '전남') 또는 NULL (전국)
  source_type public.crawl_source_type not null default 'board',
  parser_module text not null,                          -- dispatcher 가 매핑할 parser 키 (예: 'tennis-gwangju-board')
  schedule_cron text not null default '0 21 * * *',     -- pg_cron 표현식, Phase 2 에서 동적 적용
  enabled boolean not null default true,

  -- 운영 메트릭 (Phase 2/4 에서 dispatcher 가 갱신)
  last_crawled_at timestamptz,
  last_status text,                                     -- 'ok' | 'error' | 'no_change'
  last_error text,
  last_fetched_count int,
  last_etag text,                                       -- 변경 감지용 (Phase 4)
  last_modified text,                                   -- HTTP Last-Modified 헤더 (Phase 4)

  notes text,                                           -- 운영 메모

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null
);

create index if not exists crawl_sources_enabled_idx
  on public.crawl_sources (enabled, sport);
create index if not exists crawl_sources_slug_idx
  on public.crawl_sources (slug);

-- =========================================================================
-- updated_at 자동 갱신 (기존 public.touch_updated_at 재사용)
-- =========================================================================
drop trigger if exists crawl_sources_touch_updated_at on public.crawl_sources;
create trigger crawl_sources_touch_updated_at
  before update on public.crawl_sources
  for each row execute function public.touch_updated_at();

-- =========================================================================
-- RLS
--   - admin: 전체 작업 가능 (public.is_admin() SECURITY DEFINER 헬퍼 재사용)
--   - service_role: 전체 작업 (Phase 2 dispatcher 용)
--   - 그 외 일반 사용자: 접근 차단 (정책 미부여 = 거부)
-- =========================================================================
alter table public.crawl_sources enable row level security;

drop policy if exists crawl_sources_admin_all on public.crawl_sources;
create policy crawl_sources_admin_all on public.crawl_sources
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists crawl_sources_service_role_all on public.crawl_sources;
create policy crawl_sources_service_role_all on public.crawl_sources
  for all
  to service_role
  using (true)
  with check (true);

-- =========================================================================
-- Seed: 기존 3개 크롤러와 1:1 매핑
--   - URL 은 각 crawl-tennis-{slug}/index.ts 의 LIST_URL 기본값과 동일.
--   - schedule_cron 은 기존 008_cron.sql 의 21:00/21:15/21:30 KST 시각을
--     반영한 placeholder (UTC 변환은 Phase 2 dispatcher 도입 시 결정).
--   - parser_module 은 Phase 2 dispatcher 가 매핑 테이블에서 찾을 키.
-- =========================================================================
insert into public.crawl_sources
  (name, slug, url, sport, region, source_type, parser_module, schedule_cron, enabled, notes)
values
  (
    '광주테니스협회 게시판',
    'tennis-gwangju',
    'https://www.gjtennis.kr/board/list.php?bo_table=tournament',
    'tennis',
    '광주',
    'board',
    'tennis-gwangju-board',
    '0 21 * * *',
    true,
    'Phase 1 시드: 기존 crawl-tennis-gwangju Edge Function 과 1:1 매핑'
  ),
  (
    '전남테니스협회 게시판',
    'tennis-jeonnam',
    'https://jntennis.or.kr/bbs/board.php?bo_table=tournament',
    'tennis',
    '전남',
    'board',
    'tennis-jeonnam-board',
    '15 21 * * *',
    true,
    'Phase 1 시드: 기존 crawl-tennis-jeonnam Edge Function 과 1:1 매핑'
  ),
  (
    '한국테니스협회',
    'tennis-korea',
    'https://www.koreatennis.or.kr/board/tournament/list.do',
    'tennis',
    null,
    'board',
    'tennis-korea-board',
    '30 21 * * *',
    true,
    'Phase 1 시드: 기존 crawl-tennis-korea Edge Function 과 1:1 매핑'
  )
on conflict (slug) do nothing;
