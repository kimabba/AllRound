-- 일반 클럽 게시글에만 댓글을 허용한다.
-- 공지사항은 운영진 전달용이며, 모임 일정은 club_events 별도 흐름을 사용한다.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_commentable_club_post(p_post_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.club_posts p
    JOIN public.club_members m ON m.club_id = p.club_id
    WHERE p.id = p_post_id
      AND p.tag IN ('free', 'recruit', 'photo')
      AND m.user_id = (SELECT auth.uid())
      AND m.status = 'active'
  );
$$;

REVOKE ALL ON FUNCTION public.is_commentable_club_post(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_commentable_club_post(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_commentable_club_post(uuid)
  TO authenticated, service_role;

DROP POLICY IF EXISTS club_post_comments_insert
  ON public.club_post_comments;
CREATE POLICY club_post_comments_insert ON public.club_post_comments
  FOR INSERT WITH CHECK (
    author_id = (SELECT auth.uid())
    AND public.is_commentable_club_post(post_id)
  );

DROP POLICY IF EXISTS club_post_comments_select
  ON public.club_post_comments;
CREATE POLICY club_post_comments_select ON public.club_post_comments
  FOR SELECT USING (
    public.is_commentable_club_post(post_id)
    OR public.is_admin()
  );

ALTER TABLE public.club_post_comments
  DROP CONSTRAINT IF EXISTS club_post_comments_body_check;
ALTER TABLE public.club_post_comments
  ADD CONSTRAINT club_post_comments_body_check
  CHECK (length(btrim(body)) BETWEEN 1 AND 1000) NOT VALID;

COMMIT;

NOTIFY pgrst, 'reload schema';
