-- 대회 요강 AI 정형화 파이프라인: 상태 컬럼 + lease + RPC + 트리거.
-- 설계: docs/superpowers/specs/2026-07-17-tournament-regulation-ai-formatting-design.md
-- 적용: apply_migration (db push 금지). 마지막에 NOTIFY pgrst.

alter table public.tournaments
  add column if not exists format_status text not null default 'pending'
    constraint tournaments_format_status_check
    check (format_status in ('pending','processing','formatted','needs_review','failed','skipped')),
  add column if not exists format_attempts smallint not null default 0
    constraint tournaments_format_attempts_check check (format_attempts >= 0),
  add column if not exists format_claim_token uuid,
  add column if not exists claimed_at timestamptz,
  add column if not exists format_document_id uuid,
  add column if not exists format_source_hash text,
  add column if not exists format_model text,
  add column if not exists formatted_at timestamptz,
  add column if not exists format_flags jsonb
    constraint tournaments_format_flags_check
    check (format_flags is null or jsonb_typeof(format_flags) = 'array'),
  add column if not exists format_staged jsonb
    constraint tournaments_format_staged_check
    check (format_staged is null or jsonb_typeof(format_staged) = 'object'),
  add column if not exists embedding_input_revision bigint not null default 0
    constraint tournaments_embedding_input_revision_check check (embedding_input_revision >= 0);

create index if not exists tournaments_format_pending_idx
  on public.tournaments (created_at)
  where format_status = 'pending';

create or replace function public.invalidate_tournament_embedding()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if (old.title is distinct from new.title)
     or (old.description is distinct from new.description)
     or (old.region is distinct from new.region)
     or (old.format is distinct from new.format)
     or (old.organizer is distinct from new.organizer)
     or (old.regulation_fields is distinct from new.regulation_fields)
     or (old.regulation_notes is distinct from new.regulation_notes)
     or (old.regulation_body is distinct from new.regulation_body)
  then
    new.embedding := null;
    new.embedding_updated_at := null;
    new.embedding_input_revision := old.embedding_input_revision + 1;  -- 신규: 경합 방지 (Plan1)
  end if;
  return new;
end;
$function$;

create or replace function public.guard_tournament_format_columns()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
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
       or (new.embedding_input_revision is distinct from old.embedding_input_revision)
    then
      raise exception 'format_* columns are managed by the formatting pipeline';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tournaments_guard_format_columns on public.tournaments;
create trigger tournaments_guard_format_columns
  before update on public.tournaments
  for each row execute function public.guard_tournament_format_columns();

create or replace function public.format_pending_claim(
  p_batch_size int default 4,
  p_lease_minutes int default 15
) returns table (
  tournament_id uuid, title text, sport public.sport, source text,
  claim_token uuid, document_id uuid, content_hash text,
  status public.tournament_status, formatted_at timestamptz
) language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  -- (1) 만료 lease 회수: processing인데 claimed_at 초과 → attempts에 따라 pending/failed
  update public.tournaments t
     set format_status = case when t.format_attempts >= 3 then 'failed' else 'pending' end,
         format_claim_token = null, claimed_at = null
   where t.format_status = 'processing'
     and t.claimed_at < now() - make_interval(mins => p_lease_minutes);

  -- (2) pending 클레임 → processing 원자 전이
  return query
  with claimed as (
    select t.id
    from public.tournaments t
    where t.format_status = 'pending'
      and t.manual_description = false
      and t.status <> 'draft'
      and t.format_attempts < 3
      and exists (select 1 from public.crawl_documents cd where cd.tournament_id = t.id)
    order by t.created_at
    limit p_batch_size
    for update of t skip locked
  ),
  latest_doc as (
    select c.id as tid, d.id as doc_id, d.content_hash as chash
    from claimed c
    join lateral (
      select cd.id, cd.content_hash
      from public.crawl_documents cd
      where cd.tournament_id = c.id
      order by cd.fetched_at desc, cd.id desc
      limit 1
    ) d on true
  ),
  stamped as (
    update public.tournaments t
       set format_status = 'processing',
           format_attempts = t.format_attempts + 1,
           format_claim_token = gen_random_uuid(),
           claimed_at = now(),
           format_document_id = ld.doc_id
      from latest_doc ld
     where t.id = ld.tid
    returning t.id, t.title, t.sport, t.source, t.format_claim_token, t.format_document_id,
              t.status, t.formatted_at
  )
  select s.id, s.title, s.sport, s.source, s.format_claim_token, s.format_document_id, ld.chash,
         s.status, s.formatted_at
  from stamped s join latest_doc ld on ld.tid = s.id;
end;
$$;
