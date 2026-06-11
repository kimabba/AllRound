-- 054: Club favorites/scraps.
--
-- Users can bookmark clubs and view only their own saved clubs.

CREATE TABLE IF NOT EXISTS public.club_favorites (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, club_id)
);

CREATE INDEX IF NOT EXISTS club_favorites_club_id_idx
  ON public.club_favorites (club_id);

ALTER TABLE public.club_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS club_favorites_self ON public.club_favorites;
CREATE POLICY club_favorites_self ON public.club_favorites
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS club_favorites_admin_read ON public.club_favorites;
CREATE POLICY club_favorites_admin_read ON public.club_favorites
  FOR SELECT USING (public.is_admin());
