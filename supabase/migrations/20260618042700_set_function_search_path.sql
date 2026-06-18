-- Lint 0011_function_search_path_mutable 해소.
-- search_path 가 role-mutable 인 함수 11개에 고정 search_path(public)를 설정한다.
--
-- 본문은 변경하지 않고 ALTER FUNCTION 으로 proconfig 만 고정한다.
-- 주의: update_club_member_count 가 clubs/club_members 를 비수식(unqualified)으로
-- 참조하므로 ''(빈 search_path)로 고정하면 깨진다. 따라서 public 으로 고정해야
-- 기존 동작이 보존된다. vector/sport 타입과 pgvector 연산자(<=>)도 public 스키마에 존재.

ALTER FUNCTION public.crawl_release(text) SET search_path = public;
ALTER FUNCTION public.crawl_try_start(text) SET search_path = public;
ALTER FUNCTION public.invalidate_rule_embedding() SET search_path = public;
ALTER FUNCTION public.invalidate_tournament_embedding() SET search_path = public;
ALTER FUNCTION public.prevent_role_self_update() SET search_path = public;
ALTER FUNCTION public.rules_semantic_search(public.vector, public.sport, integer) SET search_path = public;
ALTER FUNCTION public.touch_updated_at() SET search_path = public;
ALTER FUNCTION public.tournament_search_by_slots(uuid, text, text, date, date, boolean, integer) SET search_path = public;
ALTER FUNCTION public.tournaments_semantic_search(uuid, public.vector, boolean, integer, text) SET search_path = public;
ALTER FUNCTION public.update_club_member_count() SET search_path = public;
ALTER FUNCTION public.venues_search(text, text, text, text, integer) SET search_path = public;
