-- 클럽 생성 시 회비를 월회비와 1회 참가비로 구분한다.
-- 생성 요청 거절 알림 유형도 통합 알림함에 추가한다.

alter table public.clubs
  add column if not exists fee_type text not null default 'monthly';

alter table public.clubs
  drop constraint if exists clubs_fee_type_check;
alter table public.clubs
  add constraint clubs_fee_type_check
  check (fee_type in ('monthly', 'per_event'));

comment on column public.clubs.fee_type is
  'monthly=월회비, per_event=1회 참가비. 금액은 기존 monthly_fee 컬럼에 저장한다.';

alter table public.notifications
  drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check check (type in (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request', 'club_creation_rejected',
    'club_inquiry_received', 'club_inquiry_reply',
    'club_dues_reminder', 'club_chat_message',
    'ranking_claim_request', 'ranking_claim_approved', 'ranking_claim_rejected'
  ));
