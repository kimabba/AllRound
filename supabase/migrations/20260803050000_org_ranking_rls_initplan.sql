-- RLS initplan 최적화: 협회 랭킹 미러 정책 4건 (JY-108 계열 후속, followup review ②)
--
-- `20260803020000_org_ranking_mirror.sql` 이 하루 전 `d28c7ff`(JY-108,
-- `20260802010000_rls_initplan_catalog_tables.sql`)에서 정리한 관례를 놓쳤다.
-- `auth.role()` / `public.is_admin()` 을 그대로 쓰면 RLS 가 행마다 함수를 재평가한다.
-- `(select ...)` 로 감싸면 Postgres 가 InitPlan 으로 한 번만 계산한다. 의미는 같다.
-- 근거: https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
--
-- DROP 없이 ALTER POLICY 로 표현식만 교체한다(정책 부재 순간 없음).
-- to authenticated 절은 그대로 유지한다 — 없으면 is_admin() 이 anon EXECUTE 권한이
-- 없어 anon 쿼리가 42501 로 죽는다(#365 에 기록된 레포 전역 결함, 이 테이블들은
-- to authenticated 로 그 결함을 피해 만들었다).

alter policy org_rankings_read on public.org_rankings
  using ((select auth.role()) = 'authenticated');

alter policy org_rankings_admin on public.org_rankings
  using ((select public.is_admin())) with check ((select public.is_admin()));

alter policy org_player_links_read on public.org_player_links
  using (
    (select auth.role()) = 'authenticated'
    and (user_id = (select auth.uid()) or status = 'confirmed')
  );

alter policy org_player_links_admin on public.org_player_links
  using ((select public.is_admin())) with check ((select public.is_admin()));
