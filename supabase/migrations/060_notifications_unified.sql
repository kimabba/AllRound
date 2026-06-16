-- 060: notifications 통합
CREATE TABLE public.notifications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE, type text NOT NULL CHECK (type IN ('tournament_d3','tournament_deadline','club_notice','club_event','club_mention','club_comment','club_event_reminder','club_attendance_change')), title text NOT NULL, body text, reference_type text, reference_id uuid, club_id uuid, is_read boolean NOT NULL DEFAULT false, status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')), error text, sent_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX notifications_user_unread_idx ON public.notifications (user_id, created_at DESC) WHERE NOT is_read;
CREATE UNIQUE INDEX notifications_dedup_idx ON public.notifications (user_id, type, reference_id) WHERE reference_id IS NOT NULL;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notifications_self_read ON public.notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY notifications_self_update ON public.notifications FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY notifications_no_user_insert ON public.notifications FOR INSERT WITH CHECK (false);
CREATE POLICY notifications_admin_all ON public.notifications FOR ALL USING (is_admin()) WITH CHECK (is_admin());

INSERT INTO public.notifications (user_id, type, title, body, reference_type, reference_id, status, sent_at, created_at) SELECT nl.user_id, CASE nl.type WHEN 'd_minus_3' THEN 'tournament_d3' WHEN 'deadline' THEN 'tournament_deadline' ELSE nl.type::text END, CASE nl.type WHEN 'd_minus_3' THEN '대회 3일 전' WHEN 'deadline' THEN '신청 마감일' ELSE '알림' END, NULL, 'tournament', nl.tournament_id, nl.status::text, nl.sent_at, nl.created_at FROM public.notifications_log nl ON CONFLICT DO NOTHING;
