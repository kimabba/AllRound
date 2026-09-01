create extension if not exists pgtap with schema extensions;

begin;
select plan(12);

select has_table(
  'public',
  'tournament_submission_contacts',
  '대회 제보 담당자 정보 테이블이 있다'
);
select col_is_pk(
  'public',
  'tournament_submission_contacts',
  array['tournament_id'],
  '대회마다 담당자 정보는 한 건만 저장한다'
);
select col_type_is(
  'public',
  'tournament_submission_contacts',
  'contact_name',
  'text',
  '담당자 이름은 text 타입이다'
);
select col_type_is(
  'public',
  'tournament_submission_contacts',
  'contact_value',
  'text',
  '담당자 연락처는 text 타입이다'
);
select is(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.tournament_submission_contacts'::regclass
  ),
  true,
  '담당자 정보 테이블은 RLS가 켜져 있다'
);
select policies_are(
  'public',
  'tournament_submission_contacts',
  array[
    'tournament_submission_contacts_read_admin',
    'tournament_submission_contacts_read_own'
  ],
  '제보자 본인과 관리자만 담당자 정보를 읽는다'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.tournament_submission_contacts',
    'SELECT'
  ),
  '비로그인 사용자는 담당자 정보를 읽을 수 없다'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.tournament_submission_contacts',
    'SELECT'
  ),
  '로그인 사용자는 RLS 범위 안에서 담당자 정보를 읽을 수 있다'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.tournament_submission_contacts',
    'INSERT'
  ),
  '클라이언트는 담당자 정보를 직접 만들 수 없다'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.tournament_submission_contacts',
    'UPDATE'
  ),
  '클라이언트는 담당자 정보를 직접 수정할 수 없다'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.tournament_submission_contacts',
    'DELETE'
  ),
  '클라이언트는 담당자 정보를 직접 삭제할 수 없다'
);
select ok(
  has_table_privilege(
    'service_role',
    'public.tournament_submission_contacts',
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  '서버는 담당자 정보를 저장하고 관리할 수 있다'
);

select * from finish();
rollback;
