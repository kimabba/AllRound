-- Account deletion spans public data and auth.users. Make the public cleanup
-- idempotent so a failed auth deletion can be retried without rolling back into
-- an unrecoverable ACCOUNT_NOT_FOUND state.

CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  DELETE FROM public.club_members WHERE user_id = p_user_id;
  DELETE FROM public.club_join_requests WHERE user_id = p_user_id;
  DELETE FROM public.club_event_attendees WHERE user_id = p_user_id;
  DELETE FROM public.gemini_usage WHERE user_id = p_user_id;
  DELETE FROM public.rate_limits WHERE user_id = p_user_id;
  DELETE FROM public.qa_cache WHERE owner_user_id = p_user_id;

  UPDATE public.club_events
  SET created_by = NULL
  WHERE created_by = p_user_id;

  DELETE FROM public.users WHERE id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_account_data(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_data(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
