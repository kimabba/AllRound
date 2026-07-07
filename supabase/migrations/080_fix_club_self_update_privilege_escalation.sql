-- 080: 클럽 권한 우회(P0) 차단 — self-UPDATE 제거
--
-- 문제: club_members_update / clubs_update 정책이 USING 만 있고 WITH CHECK 가 없어,
--   UPDATE 시 새 행 검증에 USING(user_id/created_by 만 확인)이 재사용됐다.
--   → authenticated 가 앱 anon 키 + JWT 로 PostgREST 를 직접 호출해
--     - club_members.role 을 'owner' 로 자가 승격 (클럽 탈취)
--     - clubs.status 를 'approved' 로 자가 승인 (admin 검수 우회)
--   가 가능했다 (Edge Function 의 owner/admin 서버 강제를 우회).
--
-- 수정: 두 테이블의 쓰기는 전부 Edge Function(service_role, RLS 우회) 경유이고
--   앱은 select 만 하므로, authenticated 의 직접 UPDATE 를 admin 으로 한정한다.
--   (service_role 은 RLS 를 우회하므로 정상 동작에 영향 없음)

DROP POLICY IF EXISTS club_members_update ON public.club_members;
CREATE POLICY club_members_update ON public.club_members
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

DROP POLICY IF EXISTS clubs_update ON public.clubs;
CREATE POLICY clubs_update ON public.clubs
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
