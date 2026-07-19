BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(15);

SELECT is(
  (
    SELECT count(*)
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relrowsecurity
  ),
  0::bigint,
  'public의 모든 일반·파티션 테이블에 RLS가 활성화되어 있다'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT throws_ok(
  $$UPDATE public.users
    SET role = 'admin'
    WHERE id = '00000000-0000-4000-8000-000000000005'$$,
  'P0001',
  'role 컬럼은 관리자만 변경할 수 있습니다',
  '일반 회원은 자신의 role을 admin으로 올릴 수 없다'
);

SELECT is_empty(
  $$UPDATE public.club_members
    SET role = 'owner'
    WHERE club_id = '00000000-0000-4000-8000-000000000201'
      AND user_id = '00000000-0000-4000-8000-000000000005'
    RETURNING id$$,
  '일반 회원은 자신의 클럽 역할을 owner로 올릴 수 없다'
);

SELECT is_empty(
  $$UPDATE public.clubs
    SET status = 'rejected'
    WHERE id = '00000000-0000-4000-8000-000000000201'
    RETURNING id$$,
  '일반 회원은 클럽 승인 상태를 직접 변경할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.notifications
      (user_id, type, title, status)
    VALUES
      ('00000000-0000-4000-8000-000000000005', 'club_notice', '가짜 알림', 'sent')$$,
  '42501',
  'new row violates row-level security policy for table "notifications"',
  '일반 회원은 알림을 직접 생성할 수 없다'
);

SELECT is((SELECT count(*) FROM public.club_join_requests), 0::bigint,
  '일반 클럽 회원은 다른 사용자의 가입 신청을 조회하지 못한다');
SELECT is((SELECT count(*) FROM public.club_members), 5::bigint,
  '활성 클럽 회원은 같은 클럽의 멤버 목록을 조회한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000006', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.club_join_requests), 1::bigint,
  '가입 신청자는 자신의 신청을 조회한다');
SELECT is((SELECT count(*) FROM public.club_members), 0::bigint,
  '클럽 외부인은 멤버 목록을 조회하지 못한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.club_join_requests), 1::bigint,
  '클럽 manager는 가입 신청을 조회한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.tournaments
  WHERE id BETWEEN
    '00000000-0000-4000-8000-000000000101' AND
    '00000000-0000-4000-8000-000000000104'
    AND status = 'published'), 2::bigint,
  '일반 회원은 공개 대회만 조회한다');
SELECT is((SELECT count(*) FROM public.tournaments
  WHERE id BETWEEN
    '00000000-0000-4000-8000-000000000101' AND
    '00000000-0000-4000-8000-000000000104'
    AND status IN ('draft', 'rejected')), 0::bigint,
  '일반 회원은 타인의 draft와 rejected 대회를 조회하지 못한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.tournaments WHERE id =
  '00000000-0000-4000-8000-000000000102'), 1::bigint,
  '제보자는 자신의 draft 대회를 조회한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.tournaments WHERE id BETWEEN
  '00000000-0000-4000-8000-000000000101' AND
  '00000000-0000-4000-8000-000000000104'), 4::bigint,
  '관리자는 모든 상태의 QA 대회를 조회한다');
SELECT is((SELECT count(*) FROM public.club_join_requests), 1::bigint,
  '관리자는 전체 가입 신청을 조회한다');

SELECT * FROM finish();
ROLLBACK;
