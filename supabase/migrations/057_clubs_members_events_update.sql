-- 057: clubs/members/events 수정
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS meeting_days text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS monthly_fee int;
ALTER TABLE public.clubs ADD COLUMN IF NOT EXISTS gender_preference text;
DO $$ BEGIN ALTER TABLE public.clubs ADD CONSTRAINT clubs_gender_preference_check CHECK (gender_preference IS NULL OR gender_preference IN ('male', 'female', 'mixed')); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE public.club_members ADD COLUMN IF NOT EXISTS can_kick boolean NOT NULL DEFAULT false;
ALTER TABLE public.club_members ADD COLUMN IF NOT EXISTS can_create_event boolean NOT NULL DEFAULT false;
ALTER TABLE public.club_members ADD COLUMN IF NOT EXISTS can_post_notice boolean NOT NULL DEFAULT false;
DROP POLICY IF EXISTS club_events_insert ON public.club_events;
CREATE POLICY club_events_insert ON public.club_events FOR INSERT WITH CHECK (created_by = auth.uid() AND (is_club_manager(club_id) OR EXISTS (SELECT 1 FROM public.club_members WHERE club_id = club_events.club_id AND user_id = auth.uid() AND status = 'active' AND can_create_event = true)));
DROP POLICY IF EXISTS club_events_update ON public.club_events;
CREATE POLICY club_events_update ON public.club_events FOR UPDATE USING (is_admin() OR created_by = auth.uid() OR is_club_manager(club_id)) WITH CHECK (is_admin() OR created_by = auth.uid() OR is_club_manager(club_id));
ALTER TABLE public.club_events DROP COLUMN IF EXISTS type;
