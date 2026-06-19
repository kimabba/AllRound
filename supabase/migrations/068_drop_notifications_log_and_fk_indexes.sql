-- 068: notifications_log 죽은 테이블 제거 + FK side 인덱스 (P2, 코덱스 교차검증)
--
-- 1) notifications_log: 060_notifications_unified 에서 notifications 로 이관 완료.
--    이후 신규 row 0, Edge Function(notify-cron 포함) 사용 0 → 제거.
--    전용 enum(notification_type/status)도 함께 정리.
--
-- 2) FK side 인덱스 누락 보완: FK 컬럼에 인덱스가 없으면 부모 행 삭제/검증 시
--    전체 스캔 + 락이 발생. 자주 조회/삭제되는 FK 컬럼에 인덱스 추가.

begin;

-- 1) 죽은 테이블 + 전용 enum 제거
drop table if exists public.notifications_log;
drop type if exists public.notification_type;
drop type if exists public.notification_status;

-- 2) FK side 인덱스
create index if not exists match_entries_partner_idx
  on public.match_entries (partner_id);
create index if not exists match_rounds_opponent_2_idx
  on public.match_rounds (opponent_2_id);
create index if not exists club_event_attendees_user_idx
  on public.club_event_attendees (user_id);
create index if not exists club_events_created_by_idx
  on public.club_events (created_by);

commit;
