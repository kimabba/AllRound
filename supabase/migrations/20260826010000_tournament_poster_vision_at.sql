-- P6 포스터 vision 보완 단계: 대회당 1회 호출을 보장하는 시도 기록 컬럼.
-- 포스터 이미지 AI 추출(format-pending Edge Function)은 원문 대조가 불가능하므로
-- 결과는 format_staged → needs_review 검수함 경유로만 반영된다. 이 컬럼은
-- "시도 여부"만 기록한다(성공/실패 무관 1회 — 재큐 시 재호출·비용 폭주 방지).
-- 적용: execute_sql 로 직접 적용(db push 금지). 마지막에 NOTIFY pgrst.

alter table public.tournaments
  add column if not exists poster_vision_at timestamptz;

comment on column public.tournaments.poster_vision_at is
  '포스터 이미지 AI 보완 추출을 시도한 시각. null이면 미시도. 성공/실패 무관 대회당 1회만 시도한다.';

-- 파이프라인 관리 컬럼이므로 기존 guard(포맷 컬럼 위조 방지)에 포함한다.
-- 사용자 draft update 로 이 값을 지워 vision 재호출을 유발하지 못하게 한다.
-- 아래는 20260807060617(regulation_document v1) 정의에 poster_vision_at 한 줄 추가.
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
       or (new.poster_vision_at is distinct from old.poster_vision_at)
    then
      raise exception 'format_* columns are managed by the formatting pipeline';
    end if;
  end if;
  return new;
end;
$$;

notify pgrst, 'reload schema';

-- rollback:
-- guard 함수는 20260807060617 버전(poster_vision_at 줄 제거)으로 재생성 후:
-- alter table public.tournaments drop column if exists poster_vision_at;
-- notify pgrst, 'reload schema';
