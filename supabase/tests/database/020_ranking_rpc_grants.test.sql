-- 랭킹 RPC 실행 권한 가드
--
-- 배경: 20260803030000 이 `revoke all ... from public` 으로 service_role 전용을
--   의도했으나, 프로덕션 실제 ACL 은 {postgres=X, anon=X, authenticated=X, service_role=X}
--   였다. PUBLIC(의사 롤)에서 떼는 것으로는 anon·authenticated 에 **개별 부여된** grant 가
--   지워지지 않는다. Supabase advisor 가 잡았고 20260803060000 으로 회수했다.
--
--   replace_org_ranking_division 은 org_rankings 를 부서 단위로 통째로 교체하고
--   SECURITY DEFINER 라 RLS 를 우회한다. anon key 는 공개 정보이므로 클라이언트 롤에
--   실행 권한이 남으면 누구나 랭킹을 조작할 수 있다.
--
-- 이 테스트는 그 회수가 유지되는지 지킨다. has_function_privilege 는 PUBLIC 경유든
-- 개별 grant 든 실효 권한을 보므로, 같은 함정이 다시 생기면 여기서 잡힌다.

create extension if not exists pgtap with schema extensions;

begin;
select plan(5);

-- ── replace_org_ranking_division: service_role 전용 ──────────────────
select is(
  has_function_privilege('anon',
    'public.replace_org_ranking_division(text, text, text, jsonb)', 'EXECUTE'),
  false, 'anon 은 랭킹 교체 RPC 를 실행할 수 없다');

select is(
  has_function_privilege('authenticated',
    'public.replace_org_ranking_division(text, text, text, jsonb)', 'EXECUTE'),
  false, 'authenticated 는 랭킹 교체 RPC 를 실행할 수 없다');

select is(
  has_function_privilege('service_role',
    'public.replace_org_ranking_division(text, text, text, jsonb)', 'EXECUTE'),
  true, 'service_role 은 랭킹 교체 RPC 를 실행할 수 있다 (크롤러 경로)');

-- 선수 이력 온디맨드 조회(ranking-player-history Edge Function)는 별도 RPC 없이
-- 크롤러와 같은 upsert_org_player_results(20260804010000)를 재사용한다 —
-- 그 RPC의 권한 가드는 여기서 다시 안 다룬다(이미 있으면 중복, 없으면 그 마이그레이션에서).

-- ── my_ranking_candidates: 로그인 유저 전용 ─────────────────────────
--   SECURITY INVOKER 라 anon 이 불러도 RLS 로 0행이지만, 로그인 전용 기능이라 권한도 좁힌다.
select is(
  has_function_privilege('anon', 'public.my_ranking_candidates()', 'EXECUTE'),
  false, 'anon 은 후보 조회 RPC 를 실행할 수 없다');

select is(
  has_function_privilege('authenticated', 'public.my_ranking_candidates()', 'EXECUTE'),
  true, 'authenticated 는 후보 조회 RPC 를 실행할 수 있다');

select * from finish();
rollback;
