-- Fix M-order finding: guard_tournament_format_columns must not depend on
-- alphabetical trigger fire-order relative to invalidate_tournament_embedding.
--
-- Previously the guard also blocked non-admin/non-service changes to
-- embedding_input_revision. This was only safe because
-- guard_tournament_format_columns (g...) fires alphabetically before
-- invalidate_tournament_embedding (i...), so the guard always observed the
-- un-bumped value. If a trigger were ever renamed to sort earlier, a normal
-- draft-owner content edit (which causes invalidate_tournament_embedding to
-- bump embedding_input_revision) would be wrongly rejected.
--
-- embedding_input_revision is only ever bumped by
-- invalidate_tournament_embedding (not by app code), so removing it from the
-- guard's checked columns poses negligible forgery risk while eliminating
-- the ordering dependency.

CREATE OR REPLACE FUNCTION public.guard_tournament_format_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
    then
      raise exception 'format_* columns are managed by the formatting pipeline';
    end if;
  end if;
  return new;
end;
$function$;

notify pgrst, 'reload schema';
