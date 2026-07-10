-- 크롤 주기: 활성시간 30분 간격/15분 → 하루 1회로 축소.
-- 협회 게시판은 자주 안 바뀌므로(대부분 no_change) 하루 1회면 충분하다는 운영 결정.
-- 디스패처(crawl-dispatch)의 MIN_INTERVAL_HOURS=0.4 게이트와 무관하게,
-- cron 이 하루 1회만 트리거하므로 각 enabled 소스는 하루 1회 크롤된다.
-- KST 06:00 = UTC 21:00.
--
-- 028 마이그레이션의 crawl-dispatch-regular / crawl-dispatch-last 잔재와
-- 이후 수동 변경된 crawl-dispatch(*/15) 를 모두 정리하고 단일 잡으로 통일한다.
do $$
declare
  rec record;
begin
  for rec in
    select jobid from cron.job
    where jobname in ('crawl-dispatch', 'crawl-dispatch-regular', 'crawl-dispatch-last')
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end $$;

select cron.schedule(
  'crawl-dispatch',
  '0 21 * * *',
  $$ select public.invoke_edge_function('crawl-dispatch'); $$
);
