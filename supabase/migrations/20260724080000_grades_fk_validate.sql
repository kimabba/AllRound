-- JY-146 P3-a 후속: user_sports_grade_fkey 검증.
--
-- 앞 마이그레이션(20260724070000)에서 FK 를 NOT VALID 로 붙였고 여기서 검증한다.
-- **별도 파일이어야 하는 이유**: 하나의 마이그레이션 파일은 한 트랜잭션으로 실행된다
-- (실측: 같은 파일의 두 문장이 동일한 pg_current_xact_id 를 본다). 같은 트랜잭션 안에서는
-- ADD CONSTRAINT NOT VALID 가 잡은 ACCESS EXCLUSIVE 락이 VALIDATE 의 전체 스캔 동안
-- 그대로 유지돼, 부착과 검증을 나눈 의미가 없어진다.
--
-- 파일을 나누면 VALIDATE 가 자체 트랜잭션에서 ShareUpdateExclusiveLock 만 잡으므로
-- 스캔 중에도 프로필 저장(쓰기)이 막히지 않는다.
--
-- 위반 행이 있으면 여기서 예외가 난다 — 조용히 통과시키면 정본이 두 개가 된다.
alter table public.user_sports
  validate constraint user_sports_grade_fkey;
