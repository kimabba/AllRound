-- Prevent a physical FCM token from remaining bound to multiple accounts.
-- Binding and unbinding happen through authenticated SECURITY DEFINER RPCs so
-- RLS cannot block the current user from reclaiming their own device token.

WITH ranked AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY token
      ORDER BY updated_at DESC, user_id::text
    ) AS position
  FROM public.device_tokens
)
DELETE FROM public.device_tokens AS target
USING ranked
WHERE target.ctid = ranked.ctid
  AND ranked.position > 1;

DROP INDEX IF EXISTS public.device_tokens_token_idx;
CREATE UNIQUE INDEX device_tokens_token_unique
  ON public.device_tokens (token);

CREATE OR REPLACE FUNCTION public.bind_my_device_token(
  p_token text,
  p_platform public.device_platform
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
  END IF;
  IF length(p_token) < 16 OR length(p_token) > 4096 THEN
    RAISE EXCEPTION 'invalid device token' USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.device_tokens
  WHERE token = p_token
    AND user_id <> v_user_id;

  INSERT INTO public.device_tokens (user_id, token, platform, enabled)
  VALUES (v_user_id, p_token, p_platform, true)
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        enabled = true,
        updated_at = now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.unbind_my_device_tokens()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$
  DELETE FROM public.device_tokens
  WHERE user_id = auth.uid();
$function$;

REVOKE ALL ON FUNCTION public.bind_my_device_token(text, public.device_platform)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bind_my_device_token(text, public.device_platform)
  TO authenticated;

REVOKE ALL ON FUNCTION public.unbind_my_device_tokens()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unbind_my_device_tokens()
  TO authenticated;

COMMENT ON FUNCTION public.bind_my_device_token(text, public.device_platform) IS
  'Atomically binds one physical push token to the authenticated user only.';
COMMENT ON FUNCTION public.unbind_my_device_tokens() IS
  'Removes every push token owned by the authenticated user before sign-out.';

NOTIFY pgrst, 'reload schema';
