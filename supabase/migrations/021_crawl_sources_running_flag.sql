-- 021_crawl_sources_running_flag.sql
-- Phase 2 후속 (Codex 검토 B6): 동시 실행 방지.
--
-- 배경:
--   - 15분 cron 'crawl-dispatch' + 어드민 수동 트리거가 같은 source 를 동시에 실행할 수 있다.
--   - parser 중복 실행 → 같은 listing 을 두 번 fetch + 중복 INSERT/UPDATE 위험.
--   - pg_advisory_lock 은 세션 단위라 Edge Function 의 HTTP 호출 모델과 맞지 않음
--     (connection pool 이라 매 호출 다른 세션). transaction-level lock 도 Edge Function
--     에서 트랜잭션 묶기 어려움.
--
-- 선택: DB 컬럼 단일 source of truth 패턴
--   - running_started_at timestamptz: 실행 시작 시각. NULL = 가용. 15분 초과 = stale.
--   - Edge Function crash 해도 다음 cron (15분) 에서 자동 회수.
--   - 모니터링도 SELECT 한 줄로 가능.
--
-- RPC:
--   - crawl_try_start(slug): stale 또는 NULL 일 때만 set + returning true. 그 외 NULL.
--     UPDATE ... RETURNING 의 단일 statement atomicity 로 race condition 안전.
--   - crawl_release(slug): finally 절에서 호출. NULL 로 reset.

alter table public.crawl_sources
  add column if not exists running_started_at timestamptz;

-- 시작 시도: 가용하면 set + true, 점유 중이면 (UPDATE 0행 → returning empty) NULL 반환.
-- WHERE 절의 enabled = true 는 dispatcher 가 이미 enabled 만 SELECT 하지만
-- 안전망으로 한 번 더 검증.
create or replace function public.crawl_try_start(p_slug text)
returns boolean
language sql
volatile
as $$
  update public.crawl_sources
  set running_started_at = now()
  where slug = p_slug
    and enabled = true
    and (running_started_at is null or running_started_at < now() - interval '15 minutes')
  returning true;
$$;

-- 해제. finally 절에서 호출.
create or replace function public.crawl_release(p_slug text)
returns void
language sql
volatile
as $$
  update public.crawl_sources
  set running_started_at = null
  where slug = p_slug;
$$;

revoke all on function public.crawl_try_start(text) from public;
revoke all on function public.crawl_release(text) from public;
grant execute on function public.crawl_try_start(text) to service_role;
grant execute on function public.crawl_release(text) to service_role;
