create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

select is(
  (select count(*)::integer from cron.job where jobname = 'format-pending'),
  1,
  'format-pending has exactly one cron job'
);

select is(
  (select schedule from cron.job where jobname = 'format-pending'),
  '2-59/5 * * * *',
  'format-pending runs every five minutes with a two-minute offset'
);

select ok(
  exists(
    select 1
    from cron.job
    where jobname = 'format-pending'
      and active
      and command like '%invoke_edge_function(''format-pending'')%'
  ),
  'format-pending cron is active and invokes the intended Edge Function'
);

select * from finish();
rollback;
