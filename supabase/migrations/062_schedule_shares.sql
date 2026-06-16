-- 062: schedule_shares
CREATE TABLE public.schedule_shares (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shared_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, shared_with uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, event_type text NOT NULL CHECK (event_type IN ('tournament','club_event')), event_id uuid NOT NULL, status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')), created_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT schedule_shares_no_self CHECK (shared_by != shared_with));
CREATE UNIQUE INDEX schedule_shares_dedup_idx ON public.schedule_shares (shared_by, shared_with, event_type, event_id);
CREATE INDEX schedule_shares_with_idx ON public.schedule_shares (shared_with, status);
ALTER TABLE public.schedule_shares ENABLE ROW LEVEL SECURITY;
CREATE POLICY schedule_shares_self ON public.schedule_shares FOR ALL USING (shared_by = auth.uid() OR shared_with = auth.uid()) WITH CHECK (shared_by = auth.uid());
