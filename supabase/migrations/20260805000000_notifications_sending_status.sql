-- notify-cron 의 리마인더 재시도(pending 재시도, JY 코드 리뷰 지적)에서
-- "지금 이 실행이 발송 중"임을 나타낼 별도 상태가 필요하다. 'pending' 하나로
-- "재시도 대상"과 "지금 막 선점해서 발송 중"을 같이 표현하면, 두 실행이
-- 겹칠 때 뒤 실행이 앞 실행의 진행 중인 행을 재시도 대상으로 오인해 훔쳐가
-- 중복 발송할 수 있다. 'sending'을 추가해 구분한다.
--
-- 상태 흐름: (없음|pending) --선점--> sending --sendFcm 결과--> sent|failed|pending
-- 'sending'은 다른 실행이 재시도 대상으로 보지 않는다(needsReminderAttempt).

BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT notifications_status_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_status_check
  CHECK (status IN ('pending', 'sending', 'sent', 'failed'));

COMMIT;
