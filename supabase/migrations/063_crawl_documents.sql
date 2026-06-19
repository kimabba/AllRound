-- 063: crawl_documents — 크롤 원본(raw HTML) 보관 레이어 (raw zone)
--
-- 목적:
--   - 크롤한 상세 게시글 원본 HTML 을 가공 전 상태 그대로 보관.
--   - 파서가 깨지거나 사이트 구조가 바뀌어도 재크롤 없이 raw 에서 재파싱 가능.
--   - content_hash 로 변경 감지 → 동일하면 재파싱 skip (효율).
--   - 파싱 결과(tournaments)와 tournament_id 로 연결.
--
-- 보안:
--   - raw_html 은 가공 안 된 HTML(XSS/노이즈)이라 일반 사용자에게 직접 노출 금지.
--   - service_role(크롤러 Edge Function)·admin 만 접근. 그 외 차단(정책 미부여 = 거부).
--   - 앱 원문 표시는 별도 정제 단계를 거친다(원본은 창고에만 둔다).

begin;

create table public.crawl_documents (
  id uuid primary key default gen_random_uuid(),
  source text not null,                 -- 어느 파서/소스 (crawl_audit.source 와 동일)
  source_url text not null,             -- 게시글 원본 URL (고유 식별)
  raw_html text not null,               -- 원본 HTML 통째
  content_hash text not null,           -- sha256(raw_html) — 변경 감지/재파싱 skip
  http_status int,
  fetched_at timestamptz not null default now(),
  tournament_id uuid references public.tournaments(id) on delete set null,
  parse_status text not null default 'parsed'
    check (parse_status in ('parsed', 'failed', 'pending')),
  parse_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crawl_documents_source_url_unique unique (source, source_url)
);

create index crawl_documents_tournament_idx on public.crawl_documents (tournament_id);
create index crawl_documents_source_fetched_idx on public.crawl_documents (source, fetched_at desc);
create index crawl_documents_hash_idx on public.crawl_documents (content_hash);

-- updated_at 자동 갱신 (기존 public.touch_updated_at 재사용)
drop trigger if exists crawl_documents_touch_updated_at on public.crawl_documents;
create trigger crawl_documents_touch_updated_at
  before update on public.crawl_documents
  for each row execute function public.touch_updated_at();

alter table public.crawl_documents enable row level security;

-- admin: 전체 (운영 조회/재처리)
create policy crawl_documents_admin_all on public.crawl_documents
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- service_role: 전체 (크롤러 Edge Function 이 raw 저장)
create policy crawl_documents_service_role_all on public.crawl_documents
  for all
  to service_role
  using (true)
  with check (true);

commit;
