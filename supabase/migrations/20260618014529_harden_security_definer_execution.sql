-- Harden SECURITY DEFINER functions exposed through PostgREST RPC.
--
-- The advisor flagged several SECURITY DEFINER functions as executable by
-- anon/authenticated. Keep app-facing RPCs available only to the roles that
-- need them, and make service/cron/trigger functions non-callable from clients.

BEGIN;

-- Edge Function invocation is a cron/database worker primitive. It reads the
-- internal cron JWT from Vault and must not be callable from client roles.
ALTER FUNCTION public.invoke_edge_function(text, jsonb)
  SET search_path = pg_catalog, public, vault, net;

REVOKE ALL ON FUNCTION public.invoke_edge_function(text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_edge_function(text, jsonb)
  TO postgres, service_role;

-- Semantic cache and intent classifier are called by Edge Functions with the
-- service role key. Direct client RPC access would bypass table RLS intent.
REVOKE ALL ON FUNCTION public.qa_cache_lookup(public.vector, text, real)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.qa_cache_lookup(public.vector, text, real)
  TO service_role;

REVOKE ALL ON FUNCTION public.qa_cache_insert_if_absent(
  text,
  public.vector,
  text,
  jsonb,
  text,
  timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.qa_cache_insert_if_absent(
  text,
  public.vector,
  text,
  jsonb,
  text,
  timestamptz
) TO service_role;

REVOKE ALL ON FUNCTION public.intent_classify(public.vector, real)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.intent_classify(public.vector, real)
  TO service_role;

-- Trigger-only functions should run only through their trigger context.
REVOKE ALL ON FUNCTION public.cap_device_tokens()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.handle_new_user()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.schedule_shares_guard_recipient_update()
  FROM PUBLIC, anon, authenticated;

-- App-facing RPCs: keep authenticated app calls, remove anonymous access.
REVOKE ALL ON FUNCTION public.ensure_profile()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_profile()
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.tournaments_bulk_approve(uuid[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournaments_bulk_approve(uuid[])
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.tournaments_bulk_reject(uuid[], text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournaments_bulk_reject(uuid[], text)
  TO authenticated, service_role;

COMMIT;
