-- 20260713120000: club join request/review notifications
--
-- 클럽 가입 신청/승인/거절 알림을 notifications 테이블에서 다룰 수 있게
-- type check 범위를 확장한다.

BEGIN;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected'
  ));

COMMIT;
