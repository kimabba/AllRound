ALTER TABLE public.device_tokens
  ADD COLUMN sound_enabled boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.set_my_device_token_sound(
  p_token text,
  p_sound_enabled boolean
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

  UPDATE public.device_tokens
  SET sound_enabled = p_sound_enabled,
      updated_at = now()
  WHERE user_id = v_user_id
    AND token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'device token not found' USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_my_device_token_sound(text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_device_token_sound(text, boolean)
  TO authenticated;

COMMENT ON COLUMN public.device_tokens.sound_enabled IS
  'Whether this device should receive audible push notifications.';
COMMENT ON FUNCTION public.set_my_device_token_sound(text, boolean) IS
  'Updates audible push preference for one token owned by the authenticated user.';

NOTIFY pgrst, 'reload schema';
