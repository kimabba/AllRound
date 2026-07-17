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
