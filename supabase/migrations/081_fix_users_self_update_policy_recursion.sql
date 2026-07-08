-- 081: users_self_update 정책 무한 재귀(42P17) 수정
--
-- 문제: users_self_update 의 WITH CHECK 가
--   role = (SELECT u.role FROM users u WHERE u.id = auth.uid())
-- 처럼 users 를 직접 서브쿼리로 조회했다. UPDATE 정책 평가 중 같은 테이블(users)을
-- 다시 읽으면서 정책이 재귀 → 온보딩 "시작하기"의 users UPDATE 가
-- "infinite recursion detected in policy for relation users" 로 실패했다.
--
-- role 자가 변경 방지는 이미 트리거 users_prevent_role_self_update
-- (prevent_role_self_update: admin 아니면 role 변경 시 예외)가 담당하므로,
-- WITH CHECK 의 role 서브쿼리를 제거해 재귀를 없앤다. 보안은 트리거가 유지.
DROP POLICY IF EXISTS users_self_update ON public.users;
CREATE POLICY users_self_update ON public.users
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = id)
  WITH CHECK ((SELECT auth.uid()) = id);
