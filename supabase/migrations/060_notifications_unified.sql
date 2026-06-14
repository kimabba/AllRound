-- 060: 통합 알림 테이블 (기존 notifications_log 대체)
--
-- 8종 type: tournament_d3, tournament_deadline,
--   club_notice, club_event, club_mention,
--   club_comment, club_event_reminder, club_attendance_change

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. notifications 테이블 생성
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change'
  )),
  title text NOT NULL,
  body text,
  reference_type text,
  reference_id uuid,
  club_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed')),
  error text,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 미읽 알림 빠른 조회
CREATE INDEX notifications_user_unread_idx
  ON public.notifications (user_id, created_at DESC)
  WHERE NOT is_read;

-- 중복 방지 (같은 사용자 + 타입 + 대상에 1번만)
CREATE UNIQUE INDEX notifications_dedup_idx
  ON public.notifications (user_id, type, reference_id)
  WHERE reference_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════
-- 2. RLS
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 읽기: 본인 알림만
CREATE POLICY notifications_self_read ON public.notifications
  FOR SELECT USING (user_id = auth.uid());

-- 수정: 본인 알림만 (읽음 처리)
CREATE POLICY notifications_self_update ON public.notifications
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 삽입: 사용자 직접 불가 (service_role / cron만)
CREATE POLICY notifications_no_user_insert ON public.notifications
  FOR INSERT WITH CHECK (false);

-- 어드민: 전체 접근
CREATE POLICY notifications_admin_all ON public.notifications
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ═══════════════════════════════════════════════════════════════
-- 3. 기존 notifications_log 데이터 이관
-- ═══════════════════════════════════════════════════════════════

INSERT INTO public.notifications (user_id, type, title, body, reference_type, reference_id, status, sent_at, created_at)
SELECT
  nl.user_id,
  CASE nl.type
    WHEN 'd_minus_3' THEN 'tournament_d3'
    WHEN 'deadline' THEN 'tournament_deadline'
    ELSE nl.type::text
  END,
  CASE nl.type
    WHEN 'd_minus_3' THEN '대회 3일 전'
    WHEN 'deadline' THEN '신청 마감일'
    ELSE '알림'
  END,
  NULL,
  'tournament',
  nl.tournament_id,
  nl.status::text,
  nl.sent_at,
  nl.created_at
FROM public.notifications_log nl
ON CONFLICT DO NOTHING;

COMMIT;
