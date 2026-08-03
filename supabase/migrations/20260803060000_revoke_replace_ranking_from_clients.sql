-- replace_org_ranking_division 을 클라이언트 롤에서 회수
--
-- 결함: 20260803030000 에서 `revoke all ... from public` + `grant ... to service_role` 로
--   service_role 전용을 의도했으나, 프로덕션 적용 후 실제 ACL 이
--     {postgres=X, anon=X, authenticated=X, service_role=X}
--   였다. `PUBLIC`(의사 롤)에서 떼는 것으로는 **anon·authenticated 에 개별로 부여된 grant 가
--   지워지지 않는다.** Supabase 가 새 함수에 기본 권한을 주기 때문이다.
--
-- 위험: 이 함수는 org_rankings 를 부서 단위로 통째로 교체하고 SECURITY DEFINER 라 RLS 를
--   우회한다. anon key 는 공개 정보이므로, 누구나 /rest/v1/rpc/replace_org_ranking_division
--   을 호출해 임의 협회·부서에 임의 데이터를 넣을 수 있었다(랭킹 조작).
--   Supabase advisor 의 anon_security_definer_function_executable 로 검출.
--
-- 크롤러는 service_role 로 돌므로 영향 없다.

begin;

revoke execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  from public, anon, authenticated;

grant execute on function
  public.replace_org_ranking_division(text, text, text, jsonb)
  to service_role;

-- my_ranking_candidates 는 SECURITY INVOKER 라 호출자 RLS 를 그대로 타므로
-- anon 이 불러도 0행이다. 다만 로그인 유저 전용 기능이라 anon 은 뗀다.
--
-- PUBLIC 도 함께 떼야 한다 — 이 함수의 ACL 에는 `=X/postgres`(PUBLIC grant)가 있고
-- anon 은 PUBLIC 의 멤버라, anon 개별 grant 만 회수하면 PUBLIC 경유로 여전히 실행된다.
-- (같은 함정에 두 번 걸렸다: 위 replace_org_ranking_division 이 첫 번째다.)
-- PUBLIC 을 떼면 그 경유로만 권한을 갖던 롤이 전부 잃는다. 클린 재생에서는
-- service_role 도 PUBLIC 경유가 유일한 경로라 함께 사라진다(프로덕션에는 Supabase 가 준
-- 개별 grant 가 있어 안 드러났고, 011_api_role_grants 가 이걸 잡았다).
-- 필요한 롤을 전부 명시적으로 다시 부여한다.
revoke execute on function public.my_ranking_candidates() from public, anon;
grant execute on function public.my_ranking_candidates() to authenticated, service_role;

commit;
