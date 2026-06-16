-- 061: match_entries + match_rounds
CREATE TABLE public.match_entries (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE, division text NOT NULL, partner_id uuid REFERENCES public.users(id), partner_name text, team_name text, final_round text, points_earned int NOT NULL DEFAULT 0, source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','crawl','admin')), created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX match_entries_user_idx ON public.match_entries (user_id, created_at DESC);
CREATE INDEX match_entries_tournament_idx ON public.match_entries (tournament_id);
ALTER TABLE public.match_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_entries_self ON public.match_entries FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY match_entries_partner_read ON public.match_entries FOR SELECT USING (partner_id = auth.uid());
CREATE POLICY match_entries_admin ON public.match_entries FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE TABLE public.match_rounds (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), entry_id uuid NOT NULL REFERENCES public.match_entries(id) ON DELETE CASCADE, round text NOT NULL, opponent_1_id uuid REFERENCES public.users(id), opponent_1_name text, opponent_2_id uuid REFERENCES public.users(id), opponent_2_name text, score text, result text NOT NULL CHECK (result IN ('win','lose')), played_at date, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX match_rounds_entry_idx ON public.match_rounds (entry_id);
CREATE INDEX match_rounds_opponent_idx ON public.match_rounds (opponent_1_id);
ALTER TABLE public.match_rounds ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_rounds_read ON public.match_rounds FOR SELECT USING (EXISTS (SELECT 1 FROM public.match_entries WHERE id = match_rounds.entry_id AND user_id = auth.uid()) OR opponent_1_id = auth.uid() OR opponent_2_id = auth.uid() OR is_admin());
CREATE POLICY match_rounds_write ON public.match_rounds FOR ALL USING (EXISTS (SELECT 1 FROM public.match_entries WHERE id = match_rounds.entry_id AND user_id = auth.uid()) OR is_admin()) WITH CHECK (EXISTS (SELECT 1 FROM public.match_entries WHERE id = match_rounds.entry_id AND user_id = auth.uid()) OR is_admin());
