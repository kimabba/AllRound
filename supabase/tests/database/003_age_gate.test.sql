BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(3);

SELECT lives_ok(
  $$UPDATE public.users
    SET birth_date = (current_date - interval '14 years')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '정확히 만 14세는 서버 연령 게이트를 통과한다'
);

SELECT throws_ok(
  $$UPDATE public.users
    SET birth_date = ((current_date - interval '14 years') + interval '1 day')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '23514',
  'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.',
  '만 14세에서 하루 부족하면 서버가 거부한다'
);

SELECT is(
  (SELECT count(*) FROM public.user_sports
   WHERE user_id = '00000000-0000-4000-8000-000000000008'),
  0::bigint,
  '미완성 계정은 종목 정보가 없다'
);

SELECT * FROM finish();
ROLLBACK;
