BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(11);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT throws_ok(
  $$UPDATE public.notifications
    SET title = '사용자가 바꾼 가짜 제목'
    WHERE id = '00000000-0000-4000-8000-000000000401'$$,
  '42501',
  '알림은 읽음 상태만 변경할 수 있습니다',
  '일반 회원은 서버가 만든 알림 제목을 변조할 수 없다'
);

SELECT lives_ok(
  $$UPDATE public.notifications
    SET is_read = true
    WHERE id = '00000000-0000-4000-8000-000000000401'$$,
  '일반 회원은 자신의 알림을 읽음 처리할 수 있다'
);

SELECT throws_ok(
  $$INSERT INTO public.clubs (sport, name, created_by, status)
    VALUES (
      'tennis',
      '직접 생성 우회 클럽',
      '00000000-0000-4000-8000-000000000005',
      'approved'
    )$$,
  '42501',
  'new row violates row-level security policy for table "clubs"',
  '일반 회원은 Edge Function을 우회해 클럽을 직접 만들 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.club_join_requests
      (id, club_id, user_id, message, status)
    VALUES (
      '00000000-0000-4000-8000-000000000399',
      '00000000-0000-4000-8000-000000000201',
      '00000000-0000-4000-8000-000000000005',
      '직접 가입 우회',
      'pending'
    )$$,
  '42501',
  'new row violates row-level security policy for table "club_join_requests"',
  '일반 회원은 Edge Function을 우회해 가입 신청을 직접 만들 수 없다'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

SELECT is_empty(
  $$UPDATE public.clubs
    SET status = 'approved'
    WHERE id = '00000000-0000-4000-8000-000000000201'
    RETURNING id$$,
  '클럽 생성자도 자신의 클럽을 직접 승인할 수 없다'
);

SELECT is(
  (SELECT count(*) FROM public.tournament_review_queue),
  0::bigint,
  '일반 제보자는 관리자 검수 큐를 조회하지 못한다'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

SELECT is(
  (SELECT count(*) FROM public.tournament_review_queue
   WHERE submitted_by_email = 'qa-owner@allround.invalid'),
  1::bigint,
  '관리자는 제보자 이메일이 포함된 합성 검수 항목을 조회한다'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000008', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}',
  true
);

SELECT throws_ok(
  $$UPDATE public.users
    SET birth_date = ((current_date - interval '14 years') + interval '1 day')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '23514',
  'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.',
  '실제 인증 사용자 RLS 경로에서도 만 14세 미만 생년월일을 거부한다'
);

SELECT lives_ok(
  $$UPDATE public.users
    SET birth_date = (current_date - interval '14 years')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '실제 인증 사용자 RLS 경로에서 정확히 만 14세는 허용한다'
);

SELECT throws_ok(
  $$UPDATE public.users
    SET birth_date = NULL
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '23514',
  'BIRTH_DATE_REQUIRED: 가입 완료 후 생년월일을 삭제할 수 없습니다.',
  '가입 완료 사용자는 생년월일을 지워 연령 게이트를 우회할 수 없다'
);

SELECT is(
  (SELECT role::text FROM public.users
   WHERE id = '00000000-0000-4000-8000-000000000008'),
  'user'::text,
  '연령 테스트 중에도 미완성 계정의 권한은 일반 사용자로 유지된다'
);

SELECT * FROM finish();
ROLLBACK;
