-- 020_dispatcher_cron_switch.sql
-- Phase 2: 기존 사이트별 cron 3개 DROP + crawl-dispatch 단일 cron 등록.
--
-- 운영 전환:
--   1) 008_cron.sql 의 crawl-tennis-{gwangju,jeonnam,korea}-daily job 제거
--   2) 매 15분 'crawl-dispatch' 등록 → dispatcher 가 자체적으로 source 별 schedule 평가
--      (실제 실행 판정은 dispatcher 의 MIN_INTERVAL_HOURS=20 로 "하루 1회 이상" 보장)
--
-- Idempotent:
--   - 기존 jobname 조회 후 존재할 때만 unschedule
--   - 신규 'crawl-dispatch' 도 등록 전 정리
--
-- ⚠️ 008_cron.sql 의 invoke_edge_function 함수는 그대로 재사용한다.

-- 기존 사이트별 cron job 제거 (008_cron.sql 등록분)
do $$
declare
  rec record;
begin
  for rec in
    select jobid, jobname
    from cron.job
    where jobname in (
      'crawl-tennis-gwangju-daily',
      'crawl-tennis-jeonnam-daily',
      'crawl-tennis-korea-daily'
    )
  loop
    perform cron.unschedule(rec.jobid);
    raise notice 'unscheduled cron job: % (id=%)', rec.jobname, rec.jobid;
  end loop;
end $$;

-- 기존에 같은 이름의 dispatcher job 이 있으면 정리 (재실행 안전성)
do $$
declare
  rec record;
begin
  for rec in select jobid from cron.job where jobname = 'crawl-dispatch'
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end $$;

-- 신규 dispatcher cron: 매 15분.
-- dispatcher 내부에서 enabled sources 순회 + last_crawled_at 비교로
-- 실제 실행할 source 만 추려서 처리한다. (대부분 호출은 즉시 skip → 비용 최소)
select cron.schedule(
  'crawl-dispatch',
  '*/15 * * * *',
  $$ select public.invoke_edge_function('crawl-dispatch'); $$
);
