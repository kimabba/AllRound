-- ensure_profile must match the post-055 users schema where name is NOT NULL.
-- Older definition inserted only (id, email), which fails for existing auth
-- users that do not yet have a public.users row.

BEGIN;

CREATE OR REPLACE FUNCTION public.ensure_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name)
  SELECT
    auth.uid(),
    email,
    COALESCE(raw_user_meta_data ->> 'display_name', split_part(email, '@', 1))
  FROM auth.users
  WHERE id = auth.uid()
  ON CONFLICT (id) DO UPDATE
    SET
      email = EXCLUDED.email,
      name = COALESCE(NULLIF(public.users.name, ''), EXCLUDED.name);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_profile() TO authenticated;

COMMIT;
