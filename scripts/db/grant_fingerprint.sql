-- API 롤 권한 지문(fingerprint)
--
-- 용도: 두 DB(클린 재생 vs 프로덕션, 또는 프로덕션 적용 전/후)의 권한이 같은지 증명한다.
--   양쪽에서 실행해 결과를 비교한다. hash 가 같으면 실효 권한이 동일하다.
--
-- 왜 ACL 원문이 아니라 has_*_privilege(실효 권한)로 비교하나:
--   같은 실효 권한이라도 표현이 다를 수 있다. ACL 이 비어 있는 함수는 PUBLIC 기본 EXECUTE 로
--   모두가 실행 가능한데, 프로덕션은 같은 함수에 anon/authenticated 명시 엔트리까지 갖고 있다.
--   ACL 원문을 비교하면 이 차이가 "불일치"로 잡히지만 실제 접근 결과는 동일하다.
--   우리가 보장해야 하는 것은 "누가 무엇을 할 수 있는가"이므로 실효 권한으로 비교한다.
--
-- 사용:
--   psql "$LOCAL_URL" -f scripts/db/grant_fingerprint.sql
--   (프로덕션은 읽기 전용 쿼리이므로 MCP/SQL 에디터로 같은 쿼리 실행)

with roles(who) as (
  values ('anon'), ('authenticated'), ('service_role')
),
tbl as (
  select r.who,
         'table:' || c.oid::regclass::text as obj,
         concat_ws(',',
           case when has_table_privilege(r.who, c.oid, 'SELECT') then 'S' end,
           case when has_table_privilege(r.who, c.oid, 'INSERT') then 'I' end,
           case when has_table_privilege(r.who, c.oid, 'UPDATE') then 'U' end,
           case when has_table_privilege(r.who, c.oid, 'DELETE') then 'D' end
         ) as privs
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join roles r
  where n.nspname = 'public' and c.relkind in ('r','p','v','m')
),
fn as (
  select r.who,
         'function:' || format('%I(%s)', p.proname, pg_get_function_identity_arguments(p.oid)) as obj,
         case when has_function_privilege(r.who, p.oid, 'EXECUTE') then 'X' else '' end as privs
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join roles r
  where n.nspname = 'public'
    -- 확장(pgvector 등) 소유 함수는 제외한다. 로컬 CLI 이미지와 프로덕션의 확장 버전이
    -- 달라(실측: vector 0.8.2 vs 0.8.0) 함수 개수가 어긋나는데, 이는 우리가 codify 하는
    -- 대상도 통제 대상도 아니다. 포함하면 지문이 상시 불일치라 게이트로 쓸 수 없다.
    and not exists (
      select 1 from pg_depend d
      where d.objid = p.oid and d.classid = 'pg_proc'::regclass and d.deptype = 'e'
    )
),
allrows as (
  select who, obj, privs from tbl
  union all
  select who, obj, privs from fn
)
select
  count(*) as rows,
  count(*) filter (where privs <> '') as granted,
  md5(string_agg(who || '|' || obj || '|' || privs, E'\n' order by obj, who)) as fingerprint
from allrows;
