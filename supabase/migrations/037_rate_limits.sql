-- 011_rate_limits.sql
-- 사용자별 호출 빈도 제한 — Gemini 비용 폭주 방지 (SEC-H-04).
--
-- bucket 별 (chat / semantic-search / 기타) 별도 카운터.
-- 윈도우는 초 단위 sliding (window_started_at 기준 fixed window).

create table if not exists public.rate_limits (
  user_id    uuid not null references auth.users(id) on delete cascade,
  bucket     text not null,
  window_started_at timestamptz not null default now(),
  count      int  not null default 0,
  primary key (user_id, bucket)
);

alter table public.rate_limits enable row level security;

-- service_role 만 접근 (Edge Function 에서만 호출).
create policy "rate_limits service only"
  on public.rate_limits
  for all
  to service_role
  using (true)
  with check (true);

-- 일반 사용자는 직접 read/write 불가 (정책 없음 → deny).

-- ============================================================
-- consume_rate_limit
--   현재 윈도우 내 카운트를 1 증가시키고, 한도 초과 여부를 반환.
--   윈도우가 만료됐으면 reset.
--
--   SECURITY DEFINER: service_role 키로 Edge Function 에서 호출.
--
--   Returns: (allowed bool, current_count int, reset_at timestamptz)
-- ============================================================

drop function if exists public.consume_rate_limit(uuid, text, int, int);

create or replace function public.consume_rate_limit(
  p_user_id uuid,
  p_bucket text,
  p_max_per_window int,
  p_window_seconds int
)
returns table(allowed boolean, current_count int, reset_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_window_start timestamptz;
  v_count int;
begin
  -- upsert with ON CONFLICT, 카운트는 잠금 후 처리.
  insert into rate_limits (user_id, bucket, window_started_at, count)
  values (p_user_id, p_bucket, v_now, 0)
  on conflict (user_id, bucket) do nothing;

  -- 행 잠금 후 윈도우 검사.
  select window_started_at, count
    into v_window_start, v_count
    from rate_limits
    where user_id = p_user_id and bucket = p_bucket
    for update;

  if v_window_start + (p_window_seconds || ' seconds')::interval <= v_now then
    -- 윈도우 만료 → reset.
    v_window_start := v_now;
    v_count := 0;
  end if;

  v_count := v_count + 1;

  update rate_limits
    set window_started_at = v_window_start,
        count = v_count
    where user_id = p_user_id and bucket = p_bucket;

  return query
    select v_count <= p_max_per_window,
           v_count,
           v_window_start + (p_window_seconds || ' seconds')::interval;
end;
$$;

comment on function public.consume_rate_limit is
  'token-bucket 스타일 fixed-window 카운터. allowed=false 면 호출 측에서 429 반환.';

-- Edge Function 의 user JWT 클라이언트가 호출할 수 있도록 명시적 grant.
grant execute on function public.consume_rate_limit(uuid, text, int, int)
  to authenticated, service_role;
