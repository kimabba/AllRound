-- 함수 실행 권한 가드 (#379)
--
-- 011_api_role_grants 는 **테이블** 권한을, 020_ranking_rpc_grants 는 랭킹 RPC 2개를 지킨다.
-- 그 사이 공백 — "새 함수가 anon/authenticated 에게 열린 채 배포된다" — 에서 #377 이 났다.
-- Supabase 는 새 함수에 anon·authenticated 개별 grant 를 주므로, 마이그레이션에
-- `revoke ... from public` 을 써도 실제로는 열려 있을 수 있다.
--
-- 여기서는 SQL 문장이 아니라 has_function_privilege 로 **실효 권한**을 본다.
-- PUBLIC 경유든 개별 grant 든 결과가 같으므로 같은 함정에 다시 걸리면 잡힌다.
--
-- 확장(pgvector 등) 소유 함수는 제외한다 — 우리가 관리하는 대상이 아니고
-- 로컬/프로덕션의 확장 버전이 달라 개수가 어긋난다(011 과 같은 이유).

create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

-- 1) anon 이 실행할 수 있는 함수는 **공개 검색과 순수 헬퍼뿐**이어야 한다.
--    anon key 는 앱에 박혀 배포되는 공개 정보다. 이 롤에 열린 것은 인터넷 전체에 열린 것과 같다.
--    목록 대조라 새 함수가 열린 채 들어오면 반드시 여기서 걸린다. 의도한 공개라면
--    이 목록에 이름을 추가하는 것이 그 결정을 남기는 방법이다.
select is(
  (select coalesce(string_agg(distinct p.proname, ', ' order by p.proname), '(없음)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_depend d
                       where d.objid = p.oid and d.classid = 'pg_proc'::regclass
                         and d.deptype = 'e')
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  'expand_division_codes, expand_gj_jn_codes, rules_semantic_search, '
  || 'tournament_search_by_slots, tournaments_for_user, tournaments_semantic_search, venues_search',
  'anon 이 실행할 수 있는 public 함수는 공개 검색·순수 헬퍼뿐이다'
);

-- 2) 트리거 전용 함수는 클라이언트 롤에서 실행 권한이 없어야 한다.
--    Postgres 가 직접 호출을 거부하므로("trigger functions can only be called as triggers")
--    실제 위험은 낮지만, secdef 트리거 함수는 advisor 경고로 남고 이 프로젝트의 모델은
--    "트리거 함수는 revoke + service_role 명시 부여"다(011 주석, 007 선례).
--    규칙 대조라 앞으로 추가되는 트리거 함수도 자동으로 걸린다.
--    트리거 발동에는 호출자의 EXECUTE 가 필요 없다(권한 검사는 CREATE TRIGGER 시점 1회).
select is(
  (select coalesce(string_agg(format('%s:%s', p.proname, r.who), ', '
                              order by p.proname, r.who), '(없음)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     cross join (values ('anon'),('authenticated')) as r(who)
    where n.nspname = 'public'
      and p.prorettype = 'trigger'::regtype
      and not exists (select 1 from pg_depend d
                       where d.objid = p.oid and d.classid = 'pg_proc'::regclass
                         and d.deptype = 'e')
      and has_function_privilege(r.who, p.oid, 'EXECUTE')),
  '(없음)',
  '트리거 전용 함수에 anon/authenticated 실행 권한이 없다'
);

-- 3) 서버 경로 전용 RPC 는 클라이언트 롤에서 실행할 수 없어야 한다.
--    crawl_try_start/crawl_release 는 크롤러(service_role)의 잠금이다. SECURITY INVOKER 라
--    crawl_sources 의 RLS 에 막히지만, 권한 자체를 열어 둘 이유가 없다.
--    서버 전용 함수를 새로 만들면 여기에 이름을 추가한다(랭킹 RPC 는 020 이 지킨다).
select is(
  (select coalesce(string_agg(format('%s:%s', p.proname, r.who), ', '
                              order by p.proname, r.who), '(없음)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     cross join (values ('anon'),('authenticated')) as r(who)
    where n.nspname = 'public'
      and p.proname in ('crawl_try_start', 'crawl_release')
      and has_function_privilege(r.who, p.oid, 'EXECUTE')),
  '(없음)',
  '서버 경로 전용 RPC 에 anon/authenticated 실행 권한이 없다'
);

select * from finish();
rollback;
