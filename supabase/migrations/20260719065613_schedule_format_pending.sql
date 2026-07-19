-- Keep the AI formatting worker running independently of embed-pending.
-- Offset it by two minutes so both workers do not start at the same instant.
do $$
declare
  rec record;
begin
  for rec in
    select jobid
    from cron.job
    where jobname in ('format-pending', 'format-pending-5min')
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end;
$$;

select cron.schedule(
  'format-pending',
  '2-59/5 * * * *',
  $cron$select public.invoke_edge_function('format-pending');$cron$
);
