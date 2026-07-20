-- Lint 0011_function_search_path_mutable 해소.
-- search_path 가 role-mutable 인 함수에 고정 search_path(public)를 설정한다.
--
-- 본문은 변경하지 않고 ALTER FUNCTION 으로 proconfig 만 고정한다.
-- 주의: update_club_member_count 가 clubs/club_members 를 비수식(unqualified)으로
-- 참조하므로 ''(빈 search_path)로 고정하면 깨진다. 따라서 public 으로 고정해야
-- 기존 동작이 보존된다. vector/sport 타입과 pgvector 연산자(<=>)도 public 스키마에 존재.
--
-- 숫자 prefix 마이그레이션에서 RPC 시그니처가 여러 번 교체된 뒤 이 timestamp
-- 마이그레이션이 실행된다. 로컬 reset 시 이미 제거된 과거 시그니처 때문에 전체
-- migration chain이 중단되지 않도록, 현재 존재하는 함수에만 설정을 적용한다.

DO $migration$
DECLARE
  function_signature text;
  function_regprocedure regprocedure;
BEGIN
  FOREACH function_signature IN ARRAY ARRAY[
    'public.crawl_release(text)',
    'public.crawl_try_start(text)',
    'public.invalidate_rule_embedding()',
    'public.invalidate_tournament_embedding()',
    'public.prevent_role_self_update()',
    'public.rules_semantic_search(public.vector,public.sport,integer)',
    'public.touch_updated_at()',
    'public.tournament_search_by_slots(uuid,text,text,date,date,boolean,integer)',
    'public.tournaments_semantic_search(uuid,public.vector,boolean,integer,text)',
    'public.update_club_member_count()',
    'public.venues_search(text,text,text,text,integer)'
  ]
  LOOP
    function_regprocedure := to_regprocedure(function_signature);
    IF function_regprocedure IS NULL THEN
      RAISE NOTICE 'search_path hardening skipped; function is absent: %',
        function_signature;
    ELSE
      EXECUTE format(
        'ALTER FUNCTION %s SET search_path = public',
        function_regprocedure
      );
    END IF;
  END LOOP;
END;
$migration$;
