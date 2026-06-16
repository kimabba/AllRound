-- 059: tournaments 확장 분리
CREATE TABLE public.tennis_tournament_details (tournament_id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE CASCADE, host_orgs tennis_org[] NOT NULL DEFAULT '{}', division_kta_standard text, division_gender text, division_age_group text, is_joint_event boolean NOT NULL DEFAULT false);
ALTER TABLE public.tennis_tournament_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY tennis_details_read ON public.tennis_tournament_details FOR SELECT USING (true);
CREATE POLICY tennis_details_admin ON public.tennis_tournament_details FOR ALL USING (is_admin()) WITH CHECK (is_admin());

INSERT INTO public.tennis_tournament_details (tournament_id, host_orgs, division_kta_standard, division_gender, division_age_group, is_joint_event) SELECT id, host_orgs, division_kta_standard, division_gender, division_age_group, is_joint_event FROM public.tournaments WHERE sport = 'tennis';

CREATE TABLE public.futsal_tournament_details (tournament_id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE CASCADE, host_futsal_orgs futsal_org[] NOT NULL DEFAULT '{}', venue_type text, surface_type text, match_format text, player_count int, team_count_max int, roster_min int, roster_max int);
ALTER TABLE public.futsal_tournament_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY futsal_details_read ON public.futsal_tournament_details FOR SELECT USING (true);
CREATE POLICY futsal_details_admin ON public.futsal_tournament_details FOR ALL USING (is_admin()) WITH CHECK (is_admin());

INSERT INTO public.futsal_tournament_details (tournament_id, host_futsal_orgs, venue_type, surface_type, match_format, player_count, team_count_max, roster_min, roster_max) SELECT id, host_futsal_orgs, venue_type, surface_type, match_format, player_count, team_count_max, roster_min, roster_max FROM public.tournaments WHERE sport = 'futsal';

DROP INDEX IF EXISTS tournaments_host_orgs_gin;
ALTER TABLE public.tournaments DROP COLUMN IF EXISTS host_orgs, DROP COLUMN IF EXISTS division_kta_standard, DROP COLUMN IF EXISTS division_gender, DROP COLUMN IF EXISTS division_age_group, DROP COLUMN IF EXISTS is_joint_event, DROP COLUMN IF EXISTS host_futsal_orgs, DROP COLUMN IF EXISTS venue_type, DROP COLUMN IF EXISTS surface_type, DROP COLUMN IF EXISTS match_format, DROP COLUMN IF EXISTS player_count, DROP COLUMN IF EXISTS team_count_max, DROP COLUMN IF EXISTS team_count_current, DROP COLUMN IF EXISTS roster_min, DROP COLUMN IF EXISTS roster_max;
