-- 079: 클럽 게시판 공지/일정 권한 및 알림 라우팅
--
-- 게시판 카테고리:
--   notice: 공지, 클럽장만 등록, 알림 생성
--   event: 일정, 운영진 또는 일정 권한 멤버 등록, 알림 생성
--   free: 일반, 활성 멤버 등록
--
-- 기존 recruit/photo 태그는 과거 데이터 호환을 위해 허용만 유지한다.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_club_owner(p_club_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.club_members
    WHERE club_id = p_club_id
      AND user_id = auth.uid()
      AND role = 'owner'
      AND status = 'active'
  );
$$;

ALTER TABLE public.club_posts
  DROP CONSTRAINT IF EXISTS club_posts_tag_check;

ALTER TABLE public.club_posts
  ADD CONSTRAINT club_posts_tag_check
  CHECK (tag IN ('notice', 'event', 'free', 'recruit', 'photo'));

DROP POLICY IF EXISTS club_posts_insert ON public.club_posts;
CREATE POLICY club_posts_insert ON public.club_posts
  FOR INSERT WITH CHECK (
    author_id = auth.uid()
    AND is_active_club_member(club_id)
    AND (
      tag IN ('free', 'recruit', 'photo')
      OR (tag = 'notice' AND (is_club_owner(club_id) OR is_admin()))
      OR (
        tag = 'event'
        AND (
          is_club_manager(club_id)
          OR is_admin()
          OR EXISTS (
            SELECT 1
            FROM public.club_members
            WHERE club_id = club_posts.club_id
              AND user_id = auth.uid()
              AND status = 'active'
              AND can_create_event = true
          )
        )
      )
    )
  );

DROP POLICY IF EXISTS club_posts_delete ON public.club_posts;
CREATE POLICY club_posts_delete ON public.club_posts
  FOR DELETE USING (
    is_club_owner(club_id) OR is_admin()
  );

CREATE OR REPLACE FUNCTION public.notify_club_post_targets()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tag NOT IN ('notice', 'event') THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    body,
    reference_type,
    reference_id,
    club_id
  )
  SELECT
    m.user_id,
    CASE NEW.tag
      WHEN 'notice' THEN 'club_notice'
      ELSE 'club_event'
    END,
    CASE NEW.tag
      WHEN 'notice' THEN '새 클럽 공지'
      ELSE '새 클럽 일정'
    END,
    NEW.title,
    'club_post',
    NEW.id,
    NEW.club_id
  FROM public.club_members m
  WHERE m.club_id = NEW.club_id
    AND m.status = 'active'
    AND m.user_id <> NEW.author_id
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS club_posts_notify_targets ON public.club_posts;
CREATE TRIGGER club_posts_notify_targets
  AFTER INSERT ON public.club_posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_club_post_targets();

COMMIT;
