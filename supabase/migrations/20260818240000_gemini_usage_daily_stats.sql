-- 관리자 Gemini 사용량 탭이 "오늘"만 보여주던 것에 월별 추이를 더한다.
-- gemini_usage_stats(083)와 같은 골격(security definer + is_admin() 게이트)을
-- 재사용하되, kind/model이 아니라 날짜(KST)로 묶어 일별 시계열을 반환한다.
-- p_month 를 안 주면 이번 달(KST 기준). 월 총합은 Flutter 쪽에서 이 행들을 더해
-- 계산 — RPC를 하나 더 만들 필요 없음.

create or replace function public.gemini_usage_daily_stats(p_month date default null)
returns table (
  usage_date date,
  request_count bigint,
  input_tokens bigint,
  output_tokens bigint,
  total_tokens bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month date := date_trunc(
    'month',
    coalesce(p_month, (now() at time zone 'Asia/Seoul')::date)
  )::date;
  -- KST 월 경계를 timestamptz 로 미리 계산 — g.created_at(timestamptz) 을 직접
  -- 비교해야 gemini_usage_created_at_idx 를 range scan 으로 탈 수 있다. 매 행마다
  -- (created_at at time zone ...)::date 로 캐스팅해 비교하면(옛 버전) 인덱스를
  -- 못 타 seq scan 이 된다.
  v_from timestamptz := v_month::timestamp at time zone 'Asia/Seoul';
  v_to timestamptz := (v_month + interval '1 month')::timestamp at time zone 'Asia/Seoul';
begin
  if not public.is_admin() then
    raise exception 'forbidden: admin only';
  end if;
  return query
    select
      (g.created_at at time zone 'Asia/Seoul')::date as usage_date,
      count(*)::bigint as request_count,
      coalesce(sum(g.input_tokens), 0)::bigint as input_tokens,
      coalesce(sum(g.output_tokens), 0)::bigint as output_tokens,
      coalesce(sum(g.total_tokens), 0)::bigint as total_tokens
    from public.gemini_usage g
    where g.created_at >= v_from
      and g.created_at < v_to
    group by usage_date
    order by usage_date;
end;
$$;

revoke all on function public.gemini_usage_daily_stats(date) from public, anon;
grant execute on function public.gemini_usage_daily_stats(date) to authenticated, service_role;
