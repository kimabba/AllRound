-- API 롤 권한 가드
--
-- 20260724060000_codify_api_role_grants.sql 이 부여한 권한이 유지되는지 지킨다.
-- 이 테스트가 깨지면 "마이그레이션만으로 동작하는 DB 를 재현한다"는 성질이 깨진 것이다.
--
-- 새 테이블·함수를 만드는 마이그레이션은 같은 파일에서 grant 를 명시해야 한다
-- (docs/rules/DATABASE_RULES.md). 빠뜨리면 여기서 잡힌다.
--
-- 확장(pgvector 등) 소유 함수는 제외한다 — 우리가 codify 하는 대상이 아니고
-- 로컬/프로덕션의 확장 버전이 달라 개수가 어긋난다(실측: vector 0.8.2 vs 0.8.0).

create extension if not exists pgtap with schema extensions;

begin;
select plan(5);

-- 1) 모든 public 테이블·뷰를 authenticated 가 읽을 수 있어야 한다.
--    (행 단위 통제는 RLS 가 한다. 권한이 없으면 RLS 이전에 permission denied 로 죽는다.)
select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '(없음)')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p','v','m')
      and not has_table_privilege('authenticated', c.oid, 'SELECT')),
  '(없음)',
  'authenticated 가 SELECT 못 하는 public 테이블이 없다'
);

-- 2) 클럽 문의 2개 테이블은 쓰기를 서버(Edge) 경로로만 연다.
select is(
  (select coalesce(string_agg(format('%s:%s', c.relname, r.who), ', '
                              order by c.relname, r.who), '(없음)')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     cross join (values ('anon'),('authenticated')) as r(who)
    where n.nspname = 'public'
      and c.relname in ('club_inquiry_threads','club_inquiry_messages')
      and (has_table_privilege(r.who, c.oid, 'INSERT')
        or has_table_privilege(r.who, c.oid, 'UPDATE')
        or has_table_privilege(r.who, c.oid, 'DELETE'))),
  '(없음)',
  '클럽 문의 테이블에 anon/authenticated 쓰기 권한이 없다'
);

-- 3) 모든 public 함수(확장 제외)를 service_role 이 실행할 수 있어야 한다.
--    트리거 함수는 revoke 로 PUBLIC 기본 실행권한이 사라지므로 명시 부여가 필요하다.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '(없음)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_depend d
                       where d.objid = p.oid and d.classid = 'pg_proc'::regclass
                         and d.deptype = 'e')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')),
  '(없음)',
  'service_role 이 실행 못 하는 public 함수가 없다'
);

-- 4) RLS 정책·컬럼 기본값이 의존하는 함수는 authenticated 가 실행할 수 있어야 한다.
--    has_verified_signup_age(): RLS 정책 다수가 참조 — 없으면 프로필·종목 저장이 깨진다.
--    uuid_generate_v7(): 여러 테이블의 컬럼 DEFAULT — 없으면 INSERT 가 실패한다.
select ok(
  has_function_privilege('authenticated', 'public.has_verified_signup_age()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.uuid_generate_v7()', 'EXECUTE'),
  'RLS·DEFAULT 가 의존하는 함수를 authenticated 가 실행할 수 있다'
);

-- 5) public 테이블은 전부 RLS 가 켜져 있어야 한다.
--    "테이블 권한은 넓게 + RLS 가 행 단위 통제" 모델의 전제. 하나라도 꺼지면 그대로 노출된다.
select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '(없음)')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p')
      and not c.relrowsecurity),
  '(없음)',
  'RLS 가 꺼진 public 테이블이 없다'
);

select * from finish();
rollback;
