-- 참조가 끊긴 클럽 사진을 하루 한 번 정리한다 (storage-gc).
--
-- 새벽 KST 04:00(UTC 19:00) — 업로드가 가장 적은 시간대라 "방금 올렸는데 사라졌다"가
-- 겹칠 여지를 더 줄인다(대상은 이미 24시간 지난 객체로 한정).
--
-- 같은 이름의 job 이 중복 등록되면 같은 목록을 두 번 지우려 하므로(두 번째는 404)
-- 기존 job 을 먼저 정리한다 — jobid 9·11 중복 선례.

do $$
declare
  rec record;
begin
  for rec in
    select jobid from cron.job where jobname = 'storage-gc'
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end;
$$;

select cron.schedule(
  'storage-gc',
  '0 19 * * *',
  $cron$select public.invoke_edge_function('storage-gc');$cron$
);
