-- cron.job_run_details 보존 정책 — 90일 (#332).
--
-- pg_cron 은 실행 이력을 스스로 지우지 않는다. 2026-07-26 실측 29,482행(2026-05-22~),
-- 약 2개월에 3만 행 = 연 18만 행 추세다. 잡이 늘수록 가팔라진다(현재 6개, 최다 5분마다).
--
-- 90일인 이유: 실패 상세는 edge_invocations 가 14일치를 따로 보관하므로(#329)
-- job_run_details 는 "언제 돌았나" 확인용이다. 분기 단위 회고를 남기면서 약 4.5만 행에서
-- 멈춘다.
--
-- 전용 잡으로 두는 이유: edge-invocation-sweep 함수에 끼워 넣으면 그 기능의 범위를 넘는다
-- (#329 리뷰 지적). 모든 cron 의 이력을 지우는 결정이라 자기 잡으로 분리한다.
-- qa-cache-expired-cleanup 과 같은 방식이다.
--
-- end_time IS NULL 도 지운다 — 프로세스가 죽어 완료 기록을 못 남긴 행은 영원히
-- 남는다. 이 경우엔 start_time 으로 나이를 판단한다.

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT jobid FROM cron.job WHERE jobname = 'cron-run-details-retention'
  LOOP
    PERFORM cron.unschedule(rec.jobid);
  END LOOP;
END $$;

SELECT cron.schedule(
  'cron-run-details-retention',
  '30 18 * * *', -- UTC 18:30 = KST 03:30 (다른 잡과 겹치지 않는 시각)
  $cron$DELETE FROM cron.job_run_details
        WHERE COALESCE(end_time, start_time) < now() - interval '90 days';$cron$
);
