-- clubs_select 를 로그인 롤로 좁힌다 (#365 잔여)
--
-- #381(20260803080000)이 33개 테이블의 정책을 TO authenticated 로 좁혔지만
-- clubs_select 는 **주석에만 있고 실제 alter 문이 빠져 있었다**. 프로덕션 적용 후
-- 실측에서 clubs 만 여전히 42501 이 나 발견했다(나머지 9개 테이블은 정상화).
--
-- 원래 의도는 #381 주석에 그대로 적혀 있다:
--   clubs_select 는 `status='approved' or created_by=uid or is_admin()` 형태로
--   tournaments 와 같지만, clubs 에는 contact·address·latitude/longitude 가 있어
--   승인 클럽을 비로그인에 공개하면 연락처·위치가 그대로 열린다. 그래서 tournaments
--   처럼 공개 분기를 분리하지 않고 **닫는 쪽으로** 좁힌다(2026-08-03 Commander 결정).
--
-- 동작 변화: anon 의 clubs 조회가 **42501 에러 → 0행**이 된다. 볼 수 있는 데이터는
--   전과 같이 없다(어차피 죽어서 못 봤다). 에러가 빈 결과로 바뀔 뿐이다.
--   인증 사용자·service_role(rolbypassrls)은 영향 없다.
--
-- 이 마이그레이션이 022_anon_policy_evaluation.test.sql 의 단언
-- ("anon 은 승인된 클럽도 보지 않는다", count=0)을 **프로덕션에서도 참**으로 만든다.
-- 그전까지 그 단언은 42501 이 나지 않는 환경(로컬/CI)에서만 통과했다.

begin;

alter policy clubs_select on public.clubs to authenticated;

commit;
