-- 082: club_posts pinned posts
--
-- Purpose:
--   - Allow club staff to pin important board posts.
--   - Keep normal post writing available to all active club members.
--   - Restrict pinned posts to club managers/admins at the DB layer.

BEGIN;

ALTER TABLE public.club_posts
  ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS club_posts_club_pinned_created_idx
  ON public.club_posts (club_id, is_pinned DESC, created_at DESC);

DROP POLICY IF EXISTS club_posts_insert ON public.club_posts;
CREATE POLICY club_posts_insert ON public.club_posts
  FOR INSERT WITH CHECK (
    author_id = (SELECT auth.uid())
    AND is_active_club_member(club_id)
    AND (
      is_pinned = false
      OR is_club_manager(club_id)
      OR is_admin()
    )
    AND (
      tag <> 'notice'
      OR is_club_manager(club_id)
      OR EXISTS (
        SELECT 1
        FROM public.club_members
        WHERE club_members.club_id = club_posts.club_id
          AND club_members.user_id = (SELECT auth.uid())
          AND club_members.status = 'active'
          AND club_members.can_post_notice = true
      )
    )
  );

DROP POLICY IF EXISTS club_posts_update ON public.club_posts;
CREATE POLICY club_posts_update ON public.club_posts
  FOR UPDATE USING (
    author_id = (SELECT auth.uid())
    OR is_club_manager(club_id)
    OR is_admin()
  )
  WITH CHECK (
    (
      is_pinned = false
      OR is_club_manager(club_id)
      OR is_admin()
    )
    AND (
      tag <> 'notice'
      OR is_club_manager(club_id)
      OR EXISTS (
        SELECT 1
        FROM public.club_members
        WHERE club_members.club_id = club_posts.club_id
          AND club_members.user_id = (SELECT auth.uid())
          AND club_members.status = 'active'
          AND club_members.can_post_notice = true
      )
    )
  );

COMMIT;
