-- 모든 대회 요강을 같은 정보 위계로 렌더하기 위한 versioned document contract.
-- 기존 regulation_fields/body/notes 는 구버전 앱과 검색 컨텍스트 호환을 위해 유지한다.

alter table public.tournaments
  add column regulation_document jsonb,
  add column regulation_schema_version smallint;

alter table public.tournaments
  add constraint tournaments_regulation_document_shape_check
  check (
    regulation_document is null
    or (
      jsonb_typeof(regulation_document) = 'object'
      and regulation_document ->> 'schema_version' = '1'
      and jsonb_typeof(regulation_document -> 'sections') = 'array'
    )
  ),
  add constraint tournaments_regulation_document_version_check
  check (
    (regulation_document is null and regulation_schema_version is null)
    or (
      regulation_document is not null
      and regulation_schema_version = 1
      and regulation_document ->> 'schema_version' = regulation_schema_version::text
    )
  );

comment on column public.tournaments.regulation_document is
  '표시용 대회 요강 문서 AST. v1은 고정 section code와 paragraph/subheading/bullets/key_values/table/notice/division_schedule 블록을 사용한다.';
comment on column public.tournaments.regulation_schema_version is
  'regulation_document 계약 버전. 문서가 없으면 NULL, v1 문서는 1.';

-- 문서가 바뀌면 기존 벡터가 남지 않게 embedding revision도 함께 올린다.
create or replace function public.invalidate_tournament_embedding()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if (old.title is distinct from new.title)
     or (old.description is distinct from new.description)
     or (old.region is distinct from new.region)
     or (old.format is distinct from new.format)
     or (old.organizer is distinct from new.organizer)
     or (old.regulation_document is distinct from new.regulation_document)
     or (old.regulation_fields is distinct from new.regulation_fields)
     or (old.regulation_notes is distinct from new.regulation_notes)
     or (old.regulation_body is distinct from new.regulation_body)
  then
    new.embedding := null;
    new.embedding_updated_at := null;
    new.embedding_input_revision := old.embedding_input_revision + 1;
  end if;
  return new;
end;
$function$;

-- 사용자가 draft update로 파이프라인 관리 문서를 위조하지 못하게 기존 guard 확장.
create or replace function public.guard_tournament_format_columns()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_admin() then
    if (new.format_status is distinct from old.format_status)
       or (new.format_attempts is distinct from old.format_attempts)
       or (new.format_claim_token is distinct from old.format_claim_token)
       or (new.claimed_at is distinct from old.claimed_at)
       or (new.format_document_id is distinct from old.format_document_id)
       or (new.format_source_hash is distinct from old.format_source_hash)
       or (new.format_model is distinct from old.format_model)
       or (new.formatted_at is distinct from old.formatted_at)
       or (new.format_flags is distinct from old.format_flags)
       or (new.format_staged is distinct from old.format_staged)
       or (new.regulation_document is distinct from old.regulation_document)
       or (new.regulation_schema_version is distinct from old.regulation_schema_version)
    then
      raise exception 'format_* columns are managed by the formatting pipeline';
    end if;
  end if;
  return new;
end;
$$;

-- v1 문서까지 원자적으로 반영하는 신규 RPC. 구버전 worker와 무중단 호환을 위해
-- 기존 format_pending_complete는 유지하고 별도 v2 이름을 사용한다.
create function public.format_pending_complete_v2(
  p_tid uuid,
  p_token uuid,
  p_document_id uuid,
  p_source_hash text,
  p_regulation_document jsonb,
  p_regulation_schema_version smallint,
  p_regulation_fields jsonb,
  p_regulation_notes text[],
  p_regulation_body text,
  p_prize text,
  p_format text,
  p_description text,
  p_model text,
  p_flags jsonb,
  p_stage boolean
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_rows integer;
begin
  if p_regulation_document is null
     or jsonb_typeof(p_regulation_document) <> 'object'
     or jsonb_typeof(p_regulation_document -> 'sections') <> 'array'
     or p_regulation_schema_version <> 1
     or p_regulation_document ->> 'schema_version' <> p_regulation_schema_version::text
  then
    raise exception 'invalid regulation document v1' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.crawl_documents cd
    where cd.id = p_document_id
      and cd.tournament_id = p_tid
      and cd.content_hash = p_source_hash
  ) then
    update public.tournaments
    set format_status = 'pending', format_claim_token = null, claimed_at = null
    where id = p_tid
      and format_claim_token = p_token
      and format_status = 'processing';
    return false;
  end if;

  if p_stage then
    update public.tournaments t
    set
      format_status = 'needs_review',
      format_staged = jsonb_build_object(
        'regulation_document', p_regulation_document,
        'regulation_schema_version', p_regulation_schema_version,
        'regulation_fields', coalesce(p_regulation_fields, '[]'::jsonb),
        'regulation_notes', to_jsonb(coalesce(p_regulation_notes, array[]::text[])),
        'regulation_body', p_regulation_body,
        'prize', p_prize,
        'format', p_format,
        'description', p_description
      ),
      format_model = p_model,
      format_flags = p_flags,
      format_source_hash = p_source_hash,
      format_claim_token = null,
      claimed_at = null
    where t.id = p_tid
      and t.format_claim_token = p_token
      and t.format_status = 'processing'
      and t.manual_description = false;
  else
    update public.tournaments t
    set
      regulation_document = p_regulation_document,
      regulation_schema_version = p_regulation_schema_version,
      regulation_fields = coalesce(p_regulation_fields, '[]'::jsonb),
      regulation_notes = nullif(p_regulation_notes, array[]::text[]),
      regulation_body = nullif(p_regulation_body, ''),
      prize = nullif(p_prize, ''),
      format = nullif(p_format, ''),
      description = nullif(p_description, ''),
      format_status = 'formatted',
      formatted_at = now(),
      format_model = p_model,
      format_flags = p_flags,
      format_source_hash = p_source_hash,
      format_staged = null,
      format_claim_token = null,
      claimed_at = null
    where t.id = p_tid
      and t.format_claim_token = p_token
      and t.format_status = 'processing'
      and t.manual_description = false;
  end if;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke execute on function public.format_pending_complete_v2(
  uuid, uuid, uuid, text, jsonb, smallint, jsonb, text[], text,
  text, text, text, text, jsonb, boolean
) from public, anon, authenticated;
grant execute on function public.format_pending_complete_v2(
  uuid, uuid, uuid, text, jsonb, smallint, jsonb, text[], text,
  text, text, text, text, jsonb, boolean
) to service_role;

-- 기존 검수 RPC 시그니처를 유지하면서 staged v1 문서도 함께 승인한다.
create or replace function public.format_apply_staged(
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

  if v_staged is null or v_source_hash is distinct from p_expected_source_hash then
    return false;
  end if;

  update public.tournaments t
  set
    regulation_document = coalesce(v_staged -> 'regulation_document', t.regulation_document),
    regulation_schema_version = case
      when v_staged ->> 'regulation_schema_version' = '1' then 1
      else t.regulation_schema_version
    end,
    regulation_fields = coalesce(v_staged -> 'regulation_fields', '[]'::jsonb),
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

revoke execute on function public.format_apply_staged(uuid, text)
  from public, anon;
grant execute on function public.format_apply_staged(uuid, text)
  to authenticated;

-- 기존 정형화 결과도 즉시 같은 읽기 구조를 갖게 한다. 생성형 AI를 다시
-- 호출하지 않고 이미 검수·저장된 fields/notes/body만 손실 없이 옮긴다.
-- 이후 재크롤된 대회는 format-pending이 더 세밀한 v1 블록으로 교체한다.
do $$
begin
  alter table public.tournaments disable trigger tournaments_guard_format_columns;

  with legacy_field_entries as (
    select
      t.id as tournament_id,
      case
        when normalized_label ~ '(참가부서|참가자격|출전규정|예외부서|시드기준|참가규모|경기종목)'
          then 'eligibility'
        when normalized_label ~ '(일시|일정|대회일|경기일|장소|경기장|개최지)'
          then 'schedule_venue'
        when normalized_label ~ '(환불|취소|변경)'
          then 'refund_changes'
        when normalized_label ~ '(신청|접수|참가비|입금|계좌|결제|예금주)'
          then 'registration_payment'
        when normalized_label ~ '(시상|상금|참가상품|기념품)'
          then 'awards'
        when normalized_label ~ '(경기방식|진행방식|운영|사용구|주최|주관|후원|협찬)'
          then 'match_operations'
        when normalized_label ~ '(문의|연락|전화|담당|안내)'
          then 'notices_contact'
        else 'other'
      end as section_code,
      field_order,
      jsonb_build_object('label', label, 'value', value) as entry
    from public.tournaments t
    cross join lateral (
      select
        nullif(btrim(field ->> 'label'), '') as label,
        nullif(btrim(field ->> 'value'), '') as value,
        lower(regexp_replace(field ->> 'label', '[[:space:]_\-·:/()]', '', 'g'))
          as normalized_label,
        field_order
      from jsonb_array_elements(
        case
          when jsonb_typeof(t.regulation_fields) = 'array' then t.regulation_fields
          else '[]'::jsonb
        end
      ) with ordinality as fields(field, field_order)
    ) parsed
    where t.regulation_document is null
      and label is not null
      and value is not null
  ), field_blocks as (
    select
      tournament_id,
      section_code,
      10 as block_order,
      jsonb_build_object(
        'type', 'key_values',
        'entries', jsonb_agg(entry order by field_order)
      ) as block
    from legacy_field_entries
    group by tournament_id, section_code
  ), note_blocks as (
    select
      t.id as tournament_id,
      'notices_contact'::text as section_code,
      20 as block_order,
      jsonb_build_object(
        'type', 'bullets',
        'items', jsonb_agg(to_jsonb(note) order by note_order)
      ) as block
    from public.tournaments t
    cross join lateral unnest(coalesce(t.regulation_notes, array[]::text[]))
      with ordinality as notes(raw_note, note_order)
    cross join lateral (select nullif(btrim(raw_note), '') as note) cleaned
    where t.regulation_document is null
      and note is not null
    group by t.id
  ), body_blocks as (
    select
      t.id as tournament_id,
      'other'::text as section_code,
      30 as block_order,
      jsonb_build_object('type', 'paragraph', 'text', btrim(t.regulation_body)) as block
    from public.tournaments t
    where t.regulation_document is null
      and nullif(btrim(t.regulation_body), '') is not null
  ), all_blocks as (
    select * from field_blocks
    union all
    select * from note_blocks
    union all
    select * from body_blocks
  ), section_blocks as (
    select
      tournament_id,
      section_code,
      jsonb_agg(block order by block_order) as blocks
    from all_blocks
    group by tournament_id, section_code
  ), documents as (
    select
      tournament_id,
      jsonb_build_object(
        'schema_version', 1,
        'sections', jsonb_agg(
          jsonb_build_object(
            'code', section_code,
            'availability', 'present',
            'blocks', blocks
          )
          order by case section_code
            when 'eligibility' then 10
            when 'schedule_venue' then 20
            when 'registration_payment' then 30
            when 'match_operations' then 40
            when 'awards' then 50
            when 'refund_changes' then 60
            when 'notices_contact' then 70
            else 80
          end
        )
      ) as document
    from section_blocks
    group by tournament_id
  )
  update public.tournaments t
  set
    regulation_document = documents.document,
    regulation_schema_version = 1
  from documents
  where t.id = documents.tournament_id;

  alter table public.tournaments enable trigger tournaments_guard_format_columns;
exception when others then
  alter table public.tournaments enable trigger tournaments_guard_format_columns;
  raise;
end;
$$;

notify pgrst, 'reload schema';

-- rollback:
-- drop function if exists public.format_pending_complete_v2(
--   uuid,uuid,uuid,text,jsonb,smallint,jsonb,text[],text,text,text,text,text,jsonb,boolean
-- );
-- alter table public.tournaments
--   drop constraint if exists tournaments_regulation_document_version_check,
--   drop constraint if exists tournaments_regulation_document_shape_check,
--   drop column if exists regulation_schema_version,
--   drop column if exists regulation_document;
