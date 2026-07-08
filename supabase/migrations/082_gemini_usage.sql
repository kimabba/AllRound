-- 082: Gemini API 사용량 기록 테이블.
-- Edge Function 이 service_role 로 insert (RLS 우회), 조회는 admin 만.

create table public.gemini_usage (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('llm', 'embedding')),
  model text,
  input_tokens int,
  output_tokens int,
  total_tokens int,
  user_id uuid,
  context text
);

alter table public.gemini_usage enable row level security;

-- service_role 은 RLS 우회하므로 insert 정책 불필요. admin 조회/관리만 허용.
create policy gemini_usage_admin_all on public.gemini_usage
  for all
  using (public.is_admin())
  with check (public.is_admin());

create index gemini_usage_created_at_idx on public.gemini_usage (created_at desc);
