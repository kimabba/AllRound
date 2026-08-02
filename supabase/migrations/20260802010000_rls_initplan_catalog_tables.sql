-- RLS initplan 최적화: 카탈로그 테이블 읽기 정책 (JY-108 / advisor auth_rls_initplan)
--
-- `auth.role()` 을 그대로 쓰면 RLS 가 **행마다** 함수를 재평가한다. `(select auth.role())`
-- 로 감싸면 Postgres 가 InitPlan 으로 한 번만 계산한다. 의미는 같다.
-- 근거: https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select
--
-- 대상은 남은 5건 전부 — 전에 44건이었다가 그간 대부분 정리됐고, 읽기 전용 참조
-- 데이터만 남았다(grades / regions / tennis_orgs / tennis_divisions / rule_articles).
--
-- DROP 없이 ALTER POLICY 로 바꾼다. DROP+CREATE 사이에 정책이 없는 순간이 생기면
-- 그 찰나에 들어온 요청이 거부되므로, 표현식만 교체하는 편이 안전하다.

alter policy grades_read on public.grades
  using ((select auth.role()) = 'authenticated');

alter policy regions_authenticated_read on public.regions
  using ((select auth.role()) = 'authenticated');

alter policy tennis_orgs_read on public.tennis_orgs
  using ((select auth.role()) = 'authenticated');

alter policy tennis_divisions_read on public.tennis_divisions
  using ((select auth.role()) = 'authenticated');

-- rule_articles 만 published 조건이 함께 있다. 그 조건은 그대로 둔다.
alter policy rule_articles_authenticated_read on public.rule_articles
  using ((select auth.role()) = 'authenticated' and published);
