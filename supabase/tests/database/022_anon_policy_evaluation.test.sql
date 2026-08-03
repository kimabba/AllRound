-- 비로그인(anon) 조회가 42501 로 죽지 않는지 지킨다 (#365)
--
-- 배경: is_admin() 같은 SECURITY DEFINER 헬퍼는 anon 에게 EXECUTE 가 없다(의도된 것).
--   그런데 그 함수를 부르는 RLS 정책이 `TO` 절 없이(=PUBLIC) 걸려 있으면 anon 쿼리에서도
--   평가 대상이 되고, 정책 표현식은 호출자 권한으로 평가되므로 그 자리에서 죽는다.
--   빈 결과가 아니라 **에러**다. AND/OR 단락평가로는 못 피한다(플래너가 InitPlan 으로 뽑는다).
--
--   20260803080000 적용 전 로컬 실측: RLS 테이블 33개에서 anon SELECT 가 죽었다.
--
-- 011 이 명시한 이 레포의 모델은 "테이블 권한은 넓게 + 행 통제는 RLS 가 전담"이다.
-- anon 이 못 볼 행은 0행으로 돌아와야 하고, 에러로 죽으면 그 모델이 깨진 것이다.
--
-- 단언 1 이 실제 실행 결과(정본)이고, 단언 2 는 같은 결함을 쓰기 정책에서도 잡는다
-- (SELECT 만으로는 INSERT/UPDATE/DELETE 정책의 같은 형태를 못 본다).

create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

-- 1) anon 으로 모든 RLS 테이블을 SELECT 했을 때 권한 오류가 나면 안 된다.
--    정책 평가를 실제로 시켜보는 것이므로 이게 정본이다.
--    anon 에게 테이블 SELECT 권한 자체가 없는 것(club_dues_* 등 서버·운영진 전용)은
--    의도된 설계라 제외한다 — 여기서 잡으려는 것은 "권한은 있는데 정책이 죽는" 경우다.
create function pg_temp.anon_select_failures() returns text language plpgsql as $$
declare
  r record;
  bad text[] := '{}';
begin
  for r in
    select c.oid, c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
       and has_table_privilege('anon', c.oid, 'SELECT')
     order by c.relname
  loop
    begin
      execute format('select 1 from public.%I limit 1', r.relname);
    exception when insufficient_privilege then
      bad := bad || format('%s(%s)', r.relname, sqlerrm);
    end;
  end loop;
  return coalesce(nullif(array_to_string(bad, ', '), ''), '(없음)');
end $$;

set local role anon;
select is(pg_temp.anon_select_failures(), '(없음)',
  'anon 으로 RLS 테이블을 조회할 때 권한 오류로 죽는 테이블이 없다');
reset role;

-- 2) PUBLIC 정책이 anon 이 실행 못 하는 함수를 부르면 안 된다.
--    단언 1 은 SELECT 만 실행해 보므로 쓰기 정책의 같은 결함은 못 본다.
--    카탈로그 대조라 INSERT/UPDATE/DELETE 정책까지 함께 잡는다.
select is(
  (select coalesce(string_agg(format('%s.%s', p.tablename, p.policyname), ', '
                              order by p.tablename, p.policyname), '(없음)')
     from pg_policies p
    where p.schemaname = 'public'
      and 'public' = any(p.roles)
      and exists (
        select 1
          from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
         where n.nspname = 'public'
           and not has_function_privilege('anon', pr.oid, 'EXECUTE')
           and (coalesce(p.qual, '') || ' ' || coalesce(p.with_check, ''))
               ~ ('\m' || pr.proname || '\M'))),
  '(없음)',
  'PUBLIC 정책이 anon 실행 불가 함수를 참조하지 않는다'
);

-- 3) 정책을 좁히면서 anon 의 공개 대회 조회를 잃지 않았는지.
--    tournaments_published_read 는 "공개 상태 or 본인 제출 or 관리자"였고, 뒤의 is_admin()
--    때문에 anon 이 통째로 죽었다. TO authenticated 로 좁히기만 하면 비로그인 대회 조회가
--    막히므로 공개 분기를 별도 정책으로 분리했다. 그 분리가 유지되는지 지킨다.
--    (미공개 대회가 anon 에게 새면 여기서 잡힌다.)
set local role postgres;
insert into public.tournaments (id, title, sport, start_date, status)
values ('00000000-0000-4000-8000-0000000009f1', 'zz 미공개 대회', 'tennis',
        current_date + 30, 'draft');

set local role anon;
select is(
  (select coalesce(string_agg(status::text, ', ' order by status::text), '(없음)')
     from (select distinct status from public.tournaments) s),
  'closed, published',
  'anon 은 공개 상태 대회만 보고 미공개 대회는 못 본다'
);
reset role;

select * from finish();
rollback;
