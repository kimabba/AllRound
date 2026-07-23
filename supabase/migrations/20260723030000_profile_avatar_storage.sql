BEGIN;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'profile-avatars',
  'profile-avatars',
  true,
  3145728,
  ARRAY['image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS profile_avatars_owner_select ON storage.objects;
CREATE POLICY profile_avatars_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS profile_avatars_owner_insert ON storage.objects;
CREATE POLICY profile_avatars_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS profile_avatars_owner_update ON storage.objects;
CREATE POLICY profile_avatars_owner_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
  )
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS profile_avatars_owner_delete ON storage.objects;
CREATE POLICY profile_avatars_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND owner_id = (SELECT auth.uid()::text)
  );

CREATE OR REPLACE FUNCTION public.public_storage_paths_owned_by(
  p_user_id uuid
)
RETURNS TABLE(bucket_id text, object_name text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $function$
  SELECT objects.bucket_id::text, objects.name::text
  FROM storage.objects AS objects
  WHERE objects.owner_id = p_user_id::text
    AND objects.bucket_id IN (
      'club-logos',
      'club-intro-images',
      'club-posts',
      'profile-avatars'
    );
$function$;

REVOKE ALL ON FUNCTION public.public_storage_paths_owned_by(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_storage_paths_owned_by(uuid)
  TO service_role;

COMMIT;
