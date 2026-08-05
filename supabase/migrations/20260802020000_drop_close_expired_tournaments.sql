-- close_expired_tournaments() RPC 와 close-expired-tournaments-daily cron 제거.
--
-- 왜:
--   027 이 만든 이 둘은 **프로덕션에 존재한 적이 없다**(2026-08-01 확인: pg_proc 0행,
--   cron.job 에 jobid 1·2·8·10·11·12 만). 마이그레이션 체인에는 있으므로
--   `supabase db reset` 한 로컬·CI 에만 생겨, 대회 자동 마감 로직이 환경마다 달랐다.
--
--   실제 마감은 crawl-dispatch 의 syncTournamentStatus() 가 담당한다(프로덕션·로컬 공통).
--   기준도 다르다 — RPC 는 end_date, sync 는 start_date 이고 sync 는 JY-151 이후
--   양방향(날짜 교정 시 되살리기)이다. 둘이 같은 DB 에서 돌면 한쪽이 닫은 것을
--   다른 쪽이 되살릴 수 있다.
--
--   더 중요한 건 sync 의 안전성 논거 자체가 이 부재에 기대고 있다는 점이다 —
--   supabase/functions/_shared/tournament_status.ts:8-12 는 "status='closed' 를 만드는
--   경로는 이 함수뿐이다 ... 027 의 RPC·cron 은 프로덕션에 존재하지 않는다" 를
--   되살리기가 안전한 근거로 명시한다. 로컬에서는 그 전제가 깨져 있었다.
--
-- 크롤 안 되는 대회(수동 등록·제보)도 sync 가 커버한다 — 소스와 무관하게
-- tournaments 전체를 status·start_date 로만 갱신한다.

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT jobid FROM cron.job WHERE jobname = 'close-expired-tournaments-daily'
  LOOP
    PERFORM cron.unschedule(rec.jobid);
  END LOOP;
END $$;

DROP FUNCTION IF EXISTS public.close_expired_tournaments();

NOTIFY pgrst, 'reload schema';
