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
