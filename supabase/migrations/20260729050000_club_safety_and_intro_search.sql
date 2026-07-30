-- 클럽 문의 링크 정책, 재가입 방지용 영구 차단, 가입인사 게시글을 추가한다.

BEGIN;

ALTER TABLE public.clubs
  ADD COLUMN IF NOT EXISTS inquiry_links_enabled boolean NOT NULL DEFAULT true;

CREATE TABLE public.club_bans (
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  banned_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (club_id, user_id),
  CONSTRAINT club_bans_reason_length
    CHECK (reason IS NULL OR char_length(reason) <= 300)
);

CREATE INDEX club_bans_user_idx ON public.club_bans (user_id, club_id);

ALTER TABLE public.club_bans ENABLE ROW LEVEL SECURITY;

CREATE POLICY club_bans_manager_select ON public.club_bans
  FOR SELECT USING (public.is_club_manager(club_id) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.club_bans FROM anon, authenticated;
GRANT SELECT ON public.club_bans TO authenticated;

ALTER TABLE public.club_posts DROP CONSTRAINT IF EXISTS club_posts_tag_check;
ALTER TABLE public.club_posts
  ADD CONSTRAINT club_posts_tag_check
  CHECK (tag IN ('notice', 'free', 'recruit', 'photo', 'intro'));

COMMIT;
