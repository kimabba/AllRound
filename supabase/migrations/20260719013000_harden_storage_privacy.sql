BEGIN;

-- Public buckets provide object GETs without a broad storage.objects SELECT
-- policy. Authenticated owners can still list/read their own metadata, while
-- other users cannot enumerate filenames.
DROP POLICY IF EXISTS club_logos_public_read ON storage.objects;
DROP POLICY IF EXISTS club_logos_owner_select ON storage.objects;
CREATE POLICY club_logos_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'club-logos'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS club_logos_owner_insert ON storage.objects;
CREATE POLICY club_logos_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'club-logos'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS club_logos_owner_update ON storage.objects;
CREATE POLICY club_logos_owner_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'club-logos'
    AND owner_id = (SELECT auth.uid()::text)
  )
  WITH CHECK (
    bucket_id = 'club-logos'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS club_logos_owner_delete ON storage.objects;
CREATE POLICY club_logos_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'club-logos'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS club_intro_images_public_read ON storage.objects;
DROP POLICY IF EXISTS club_intro_images_owner_select ON storage.objects;
CREATE POLICY club_intro_images_owner_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'club-intro-images'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS club_intro_images_owner_insert ON storage.objects;
CREATE POLICY club_intro_images_owner_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'club-intro-images'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS club_intro_images_owner_update ON storage.objects;
CREATE POLICY club_intro_images_owner_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'club-intro-images'
    AND owner_id = (SELECT auth.uid()::text)
  )
  WITH CHECK (
    bucket_id = 'club-intro-images'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS club_intro_images_owner_delete ON storage.objects;
CREATE POLICY club_intro_images_owner_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'club-intro-images'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS club_posts_storage_select ON storage.objects;
CREATE POLICY club_posts_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'club-posts'
    AND owner_id = (SELECT auth.uid()::text)
  );

DROP POLICY IF EXISTS club_posts_storage_insert ON storage.objects;
CREATE POLICY club_posts_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'club-posts'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS club_posts_storage_delete ON storage.objects;
CREATE POLICY club_posts_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'club-posts'
    AND owner_id = (SELECT auth.uid()::text)
  );

-- Moderation evidence stays private. The reporter folder remains for the
-- existing create_ugc_report path contract, but authorization no longer trusts
-- that user-controlled folder and instead uses the JWT-derived owner_id.
DROP POLICY IF EXISTS ugc_report_evidence_insert ON storage.objects;
CREATE POLICY ugc_report_evidence_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'ugc-report-evidence'
    AND owner_id = (SELECT auth.uid()::text)
    AND (SELECT public.has_verified_signup_age())
  );

DROP POLICY IF EXISTS ugc_report_evidence_select ON storage.objects;
CREATE POLICY ugc_report_evidence_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'ugc-report-evidence'
    AND (
      owner_id = (SELECT auth.uid()::text)
      OR (SELECT public.is_admin())
    )
  );

DROP POLICY IF EXISTS ugc_report_evidence_delete ON storage.objects;
CREATE POLICY ugc_report_evidence_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'ugc-report-evidence'
    AND (
      owner_id = (SELECT auth.uid()::text)
      OR (SELECT public.is_admin())
    )
  );

-- The account-deletion Edge Function asks for exact public object paths before
-- deleting the user's public row. The function is service-role only and never
-- exposes another user's Storage inventory to an app session.
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
      'club-posts'
    );
$function$;

REVOKE ALL ON FUNCTION public.public_storage_paths_owned_by(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_storage_paths_owned_by(uuid)
  TO service_role;

-- Keep authored text for community continuity, but remove public media links
-- and UUIDs that identify the deleted account. Private moderation evidence is
-- deliberately excluded until the legal retention period is finalized.
CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  UPDATE public.club_posts AS post
  SET image_urls = COALESCE(
    ARRAY(
      SELECT image_url
      FROM unnest(post.image_urls) AS image_url
      WHERE NOT EXISTS (
        SELECT 1
        FROM storage.objects AS object
        WHERE object.owner_id = p_user_id::text
          AND object.bucket_id = 'club-posts'
          AND strpos(image_url, '/club-posts/' || object.name) > 0
      )
    ),
    '{}'::text[]
  )
  WHERE EXISTS (
    SELECT 1
    FROM unnest(post.image_urls) AS image_url
    JOIN storage.objects AS object
      ON object.owner_id = p_user_id::text
     AND object.bucket_id = 'club-posts'
     AND strpos(image_url, '/club-posts/' || object.name) > 0
  );

  UPDATE public.clubs AS club
  SET logo_url = NULL
  WHERE club.logo_url IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM storage.objects AS object
      WHERE object.owner_id = p_user_id::text
        AND object.bucket_id = 'club-logos'
        AND strpos(club.logo_url, '/club-logos/' || object.name) > 0
    );

  UPDATE public.clubs AS club
  SET intro_image_urls = COALESCE(
    ARRAY(
      SELECT image_url
      FROM unnest(club.intro_image_urls) AS image_url
      WHERE NOT EXISTS (
        SELECT 1
        FROM storage.objects AS object
        WHERE object.owner_id = p_user_id::text
          AND object.bucket_id = 'club-intro-images'
          AND strpos(image_url, '/club-intro-images/' || object.name) > 0
      )
    ),
    '{}'::text[]
  )
  WHERE EXISTS (
    SELECT 1
    FROM unnest(club.intro_image_urls) AS image_url
    JOIN storage.objects AS object
      ON object.owner_id = p_user_id::text
     AND object.bucket_id = 'club-intro-images'
     AND strpos(image_url, '/club-intro-images/' || object.name) > 0
  );

  UPDATE public.ugc_reports
  SET content_snapshot = replace(
    content_snapshot::text,
    p_user_id::text,
    'deleted-user'
  )::jsonb
  WHERE content_snapshot::text LIKE '%' || p_user_id::text || '%';

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

COMMIT;
