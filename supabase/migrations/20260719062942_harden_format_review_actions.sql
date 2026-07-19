-- Make admin review actions deterministic:
-- 1) reject validation-failure rows even when format_staged is null;
-- 2) refuse stale actions after the crawler source hash changes.

drop function if exists public.format_apply_staged(uuid);
drop function if exists public.format_apply_staged(uuid, text);

create function public.format_apply_staged(
  p_tid uuid,
  p_expected_source_hash text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_staged jsonb;
  v_source_hash text;
  v_rows integer;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;

  select t.format_staged, t.format_source_hash
    into v_staged, v_source_hash
  from public.tournaments t
  where t.id = p_tid
    and t.format_status = 'needs_review';

  if v_staged is null
     or v_source_hash is distinct from p_expected_source_hash
  then
    return false;
  end if;

  update public.tournaments t
  set
    regulation_fields = coalesce(
      v_staged -> 'regulation_fields',
      '[]'::jsonb
    ),
    regulation_notes = nullif(
      array(
        select value
        from jsonb_array_elements_text(
          coalesce(v_staged -> 'regulation_notes', '[]'::jsonb)
        ) as notes(value)
      ),
      array[]::text[]
    ),
    regulation_body = nullif(v_staged ->> 'regulation_body', ''),
    prize = nullif(v_staged ->> 'prize', ''),
    format = nullif(v_staged ->> 'format', ''),
    description = nullif(v_staged ->> 'description', ''),
    format_status = 'formatted',
    formatted_at = now(),
    format_staged = null
  where t.id = p_tid
    and t.format_status = 'needs_review'
    and t.format_staged is not null
    and t.format_source_hash is not distinct from p_expected_source_hash
    and (
      select cd.content_hash
      from public.crawl_documents cd
      where cd.tournament_id = t.id
      order by cd.fetched_at desc, cd.id desc
      limit 1
    ) is not distinct from p_expected_source_hash;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

drop function if exists public.format_reject_staged(uuid, text);
drop function if exists public.format_reject_staged(uuid, text, text);

create function public.format_reject_staged(
  p_tid uuid,
  p_expected_source_hash text,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_reason text := left(trim(coalesce(p_reason, '')), 200);
  v_rows integer;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if v_reason = '' then
    raise exception 'rejection reason required' using errcode = '22023';
  end if;

  update public.tournaments t
  set
    format_status = 'failed',
    format_staged = null,
    format_flags = coalesce(t.format_flags, '[]'::jsonb) ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'admin_reject',
          'field', '_admin',
          'masked', v_reason
        )
      )
  where t.id = p_tid
    and t.format_status = 'needs_review'
    and t.format_source_hash is not distinct from p_expected_source_hash
    and (
      select cd.content_hash
      from public.crawl_documents cd
      where cd.tournament_id = t.id
      order by cd.fetched_at desc, cd.id desc
      limit 1
    ) is not distinct from p_expected_source_hash;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke execute on function public.format_apply_staged(uuid, text)
  from public, anon;
revoke execute on function public.format_reject_staged(uuid, text, text)
  from public, anon;

grant execute on function public.format_apply_staged(uuid, text)
  to authenticated;
grant execute on function public.format_reject_staged(uuid, text, text)
  to authenticated;

notify pgrst, 'reload schema';
