-- 요강 정형화 검수 스테이징 승인/반려 RPC (admin 전용).
create or replace function public.format_apply_staged(p_tid uuid)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare s jsonb; v int;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  select format_staged into s from public.tournaments where id = p_tid;
  if s is null then return false; end if;
  update public.tournaments t set
    regulation_fields = s -> 'regulation_fields',
    regulation_notes = (
      select array_agg(x)::text[]
      from jsonb_array_elements_text(coalesce(s -> 'regulation_notes', '[]'::jsonb)) x
    ),
    regulation_body = nullif(s ->> 'regulation_body', ''),
    prize = nullif(s ->> 'prize', ''),
    format = nullif(s ->> 'format', ''),
    description = nullif(s ->> 'description', ''),
    format_status = 'formatted', formatted_at = now(), format_staged = null
  where t.id = p_tid;
  get diagnostics v = row_count;
  return v > 0;
end;
$$;

create or replace function public.format_reject_staged(p_tid uuid, p_reason text)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
declare v int;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  update public.tournaments t set
    format_status = 'failed', format_staged = null,
    format_flags = coalesce(t.format_flags, '[]'::jsonb) ||
      jsonb_build_array(jsonb_build_object('code','admin_reject','field','_admin',
        'masked', left(coalesce(p_reason,''), 200)))
  where t.id = p_tid and t.format_staged is not null;
  get diagnostics v = row_count;
  return v > 0;
end;
$$;

revoke execute on function public.format_apply_staged(uuid) from public, anon;
revoke execute on function public.format_reject_staged(uuid, text) from public, anon;
grant execute on function public.format_apply_staged(uuid) to authenticated;   -- 내부 is_admin() 게이트
grant execute on function public.format_reject_staged(uuid, text) to authenticated;

notify pgrst, 'reload schema';
