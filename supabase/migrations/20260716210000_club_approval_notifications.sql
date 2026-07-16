-- 클럽 생성 후 관리자 승인 요청 알림을 통합 알림함에 저장한다.

BEGIN;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request'
  ));

-- 배포 전에 이미 들어온 승인 대기 요청도 관리자 알림함에 한 번만 채운다.
INSERT INTO public.notifications (
  user_id,
  type,
  title,
  body,
  reference_type,
  reference_id,
  club_id,
  status
)
SELECT
  admin_user.id,
  'club_approval_request',
  '새 클럽 승인 요청',
  format('“%s” 클럽이 승인을 기다리고 있습니다.', club.name),
  'club_approval_request',
  club.id,
  club.id,
  'sent'
FROM public.clubs AS club
CROSS JOIN public.users AS admin_user
WHERE club.status = 'pending'
  AND admin_user.role = 'admin'
ON CONFLICT DO NOTHING;

COMMIT;
