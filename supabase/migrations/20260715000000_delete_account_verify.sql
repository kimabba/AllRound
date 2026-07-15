-- 20260715000000_delete_account_verify.sql
-- JY-112 후속: 회원 탈퇴 "조용한 실패" 방지.
--
-- 기존 delete_account_data 는 DELETE 대상이 없어도(stale/orphan 세션으로 잘못된 uid 가
-- 넘어온 경우) 아무 예외 없이 성공 반환 → Edge 가 200("탈퇴 완료")을 주고 앱은 탈퇴된
-- 것으로 표시하지만 실제 개인정보는 남는다(개인정보보호법 §21 위반 소지).
--
-- 수정: users 삭제가 0건이면 예외를 던져 RPC 를 실패시키고, Edge(delete-account)가 500 을
-- 반환하게 한다 → 앱이 "탈퇴 실패, 재로그인 후 재시도"를 안내. 정상 케이스는 무영향.

CREATE OR REPLACE FUNCTION public.delete_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.club_members WHERE user_id = p_user_id;
  DELETE FROM public.club_join_requests WHERE user_id = p_user_id;
  DELETE FROM public.club_event_attendees WHERE user_id = p_user_id;
  DELETE FROM public.gemini_usage WHERE user_id = p_user_id;
  DELETE FROM public.rate_limits WHERE user_id = p_user_id;
  UPDATE public.club_events SET created_by = NULL WHERE created_by = p_user_id;

  DELETE FROM public.users WHERE id = p_user_id;
  -- 삭제할 계정이 실제로 없었으면(stale/orphan uid) 조용히 넘어가지 않고 실패시킨다.
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      errcode = 'no_data_found',
      message = 'ACCOUNT_NOT_FOUND: 삭제할 계정이 없습니다.';
  END IF;
END;
$function$;
