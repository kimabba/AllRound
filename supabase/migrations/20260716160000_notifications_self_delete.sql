-- 사용자는 본인 알림만 알림함에서 삭제할 수 있다.
DROP POLICY IF EXISTS notifications_self_delete ON public.notifications;

CREATE POLICY notifications_self_delete ON public.notifications
  FOR DELETE
  USING ((SELECT auth.uid()) = user_id);
