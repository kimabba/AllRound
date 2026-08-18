-- 관리자도 자신의 알림만 읽고 읽음 처리한다.
-- 알림 생성은 service_role이 관리자마다 한 건씩 담당하므로 전체 접근 정책은 불필요하다.

drop policy if exists notifications_admin_all on public.notifications;
