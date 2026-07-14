-- 공개 팀원 모집글. 참여 신청은 기존 club_join_requests 흐름을 재사용한다.

BEGIN;

CREATE TABLE public.club_recruiting_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  intro text CHECK (intro IS NULL OR length(intro) <= 1000),
  place text NOT NULL CHECK (length(btrim(place)) BETWEEN 1 AND 200),
  schedule_text text NOT NULL CHECK (length(btrim(schedule_text)) BETWEEN 1 AND 200),
  skill_level text NOT NULL CHECK (length(btrim(skill_level)) BETWEEN 1 AND 100),
  gender_text text NOT NULL CHECK (length(btrim(gender_text)) BETWEEN 1 AND 50),
  age_text text NOT NULL CHECK (length(btrim(age_text)) BETWEEN 1 AND 50),
  position_text text CHECK (position_text IS NULL OR length(position_text) <= 100),
  field_count integer NOT NULL DEFAULT 0 CHECK (field_count BETWEEN 0 AND 100),
  keeper_count integer NOT NULL DEFAULT 0 CHECK (keeper_count BETWEEN 0 AND 20),
  total_count integer NOT NULL CHECK (total_count BETWEEN 1 AND 100),
  cost_text text NOT NULL DEFAULT '협의' CHECK (length(btrim(cost_text)) BETWEEN 1 AND 100),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_recruiting_closed_at_check CHECK (
    (status = 'open' AND closed_at IS NULL)
    OR (status = 'closed' AND closed_at IS NOT NULL)
  )
);

CREATE INDEX club_recruiting_posts_status_created_idx
  ON public.club_recruiting_posts (status, created_at DESC);

CREATE INDEX club_recruiting_posts_club_created_idx
  ON public.club_recruiting_posts (club_id, created_at DESC);

CREATE TRIGGER club_recruiting_posts_touch_updated_at
  BEFORE UPDATE ON public.club_recruiting_posts
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.club_recruiting_posts ENABLE ROW LEVEL SECURITY;

-- 승인된 클럽의 모집글은 로그인 사용자에게 공개한다.
-- 승인 전 클럽은 해당 클럽 멤버와 관리자만 확인할 수 있다.
CREATE POLICY club_recruiting_posts_select ON public.club_recruiting_posts
  FOR SELECT USING (
    (SELECT auth.uid()) IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.clubs c
        WHERE c.id = club_recruiting_posts.club_id
          AND c.status = 'approved'
      )
      OR public.is_active_club_member(club_id)
      OR public.is_admin()
    )
  );

CREATE POLICY club_recruiting_posts_insert ON public.club_recruiting_posts
  FOR INSERT WITH CHECK (
    created_by = (SELECT auth.uid())
    AND (public.is_club_manager(club_id) OR public.is_admin())
  );

CREATE POLICY club_recruiting_posts_update ON public.club_recruiting_posts
  FOR UPDATE USING (
    public.is_club_manager(club_id) OR public.is_admin()
  ) WITH CHECK (
    public.is_club_manager(club_id) OR public.is_admin()
  );

CREATE POLICY club_recruiting_posts_delete ON public.club_recruiting_posts
  FOR DELETE USING (
    public.is_club_manager(club_id) OR public.is_admin()
  );

COMMIT;
