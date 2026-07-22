BEGIN;

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'tournament-posters',
  'tournament-posters',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS tournament_posters_owner_select ON storage.objects;
CREATE POLICY tournament_posters_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'tournament-posters'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS tournament_posters_owner_insert ON storage.objects;
CREATE POLICY tournament_posters_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'tournament-posters'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS tournament_posters_owner_delete ON storage.objects;
CREATE POLICY tournament_posters_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'tournament-posters'
    AND owner_id = (SELECT auth.uid()::text)
  );

COMMIT;
