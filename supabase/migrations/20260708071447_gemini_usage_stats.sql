-- gemini_usage 집계 RPC. 관리자 대시보드가 kind·model별 요청수/토큰을 서버에서
-- 집계해 받도록 함 (전체 로우를 클라이언트로 끌어오는 것 방지).
--
-- SECURITY DEFINER 이므로 반드시 is_admin() 게이트. anon 실행 차단.

create or replace function public.gemini_usage_stats(p_since timestamptz)
returns table (
  kind text,
  model text,
  request_count bigint,
  input_tokens bigint,
  output_tokens bigint,
  total_tokens bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'forbidden: admin only';
  end if;
  return query
    select
      g.kind,
      coalesce(g.model, '(unknown)') as model,
      count(*)::bigint as request_count,
      coalesce(sum(g.input_tokens), 0)::bigint as input_tokens,
      coalesce(sum(g.output_tokens), 0)::bigint as output_tokens,
      coalesce(sum(g.total_tokens), 0)::bigint as total_tokens
    from public.gemini_usage g
    where g.created_at >= p_since
    group by g.kind, coalesce(g.model, '(unknown)')
    order by g.kind, coalesce(g.model, '(unknown)');
end;
$$;

revoke all on function public.gemini_usage_stats(timestamptz) from public, anon;
grant execute on function public.gemini_usage_stats(timestamptz) to authenticated;
