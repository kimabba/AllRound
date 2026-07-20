-- Trigger functions are invoked by Postgres, never directly through the Data API.
-- Explicitly remove the default PUBLIC execute grant and any legacy role grants.
revoke execute on function public.enforce_ugc_text_policy()
  from public, anon, authenticated;

-- The tournament-format pipeline is already live in production but its source PR
-- is being reconciled separately. Keep this migration reset-safe until that
-- earlier migration is present in every checkout.
do $$
begin
  if to_regprocedure('public.guard_tournament_format_columns()') is not null then
    revoke execute on function public.guard_tournament_format_columns()
      from public, anon, authenticated;
  end if;
end;
$$;

-- Event responses are a signed-in member action. A legacy anon grant exposed the
-- SECURITY DEFINER RPC without authentication, even though the body validates
-- membership. Keep the intended authenticated path and close the anonymous one.
revoke execute on function public.respond_club_event(uuid, text)
  from public, anon;

grant execute on function public.respond_club_event(uuid, text)
  to authenticated;
