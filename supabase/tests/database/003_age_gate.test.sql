BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(10);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000008', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000008","role":"authenticated"}',
  true
);

SELECT is(
  public.has_verified_signup_age(),
  false,
  '생년월일이 없는 가입 직후 계정은 연령 검증 전 상태다'
);

SELECT throws_ok(
  $$INSERT INTO public.user_sports (user_id, sport, grade, is_primary)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      'futsal',
      'intro',
      true
    )$$,
  '42501',
  'new row violates row-level security policy for table "user_sports"',
  '생년월일이 없는 계정은 종목을 등록할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.tournaments
      (sport, title, start_date, source, status, submitted_by)
    VALUES (
      'tennis',
      '연령 검증 전 직접 제보',
      current_date + 30,
      'user_submission',
      'draft',
      '00000000-0000-4000-8000-000000000008'
    )$$,
  '42501',
  'new row violates row-level security policy for table "tournaments"',
  '생년월일이 없는 계정은 대회를 제보할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.user_tennis_orgs
      (user_id, org, division, division_codes, is_primary, region_code)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      'kta',
      '연령 검증 전 부서',
      ARRAY['kta_m_open'],
      true,
      'seoul'
    )$$,
  '42501',
  'new row violates row-level security policy for table "user_tennis_orgs"',
  '생년월일이 없는 계정은 협회 등급을 등록할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.chat_messages
      (user_id, conversation_id, role, content)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      gen_random_uuid(),
      'user',
      '연령 검증 전 메시지'
    )$$,
  '42501',
  'new row violates row-level security policy for table "chat_messages"',
  '생년월일이 없는 계정은 AI 대화를 저장할 수 없다'
);

SELECT lives_ok(
  $$UPDATE public.users
    SET birth_date = (current_date - interval '14 years')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '정확히 만 14세는 서버 연령 게이트를 통과한다'
);

SELECT is(
  public.has_verified_signup_age(),
  true,
  '정확히 만 14세 생년월일을 저장하면 연령 검증이 완료된다'
);

SELECT lives_ok(
  $$INSERT INTO public.user_sports (user_id, sport, grade, is_primary)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      'futsal',
      'intro',
      true
    )$$,
  '연령 검증을 마친 계정은 종목을 등록할 수 있다'
);

SELECT lives_ok(
  $$INSERT INTO public.chat_messages
      (user_id, conversation_id, role, content)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      gen_random_uuid(),
      'user',
      '연령 검증 후 메시지'
    )$$,
  '연령 검증을 마친 계정은 AI 대화를 저장할 수 있다'
);

SELECT throws_ok(
  $$UPDATE public.users
    SET birth_date = ((current_date - interval '14 years') + interval '1 day')::date
    WHERE id = '00000000-0000-4000-8000-000000000008'$$,
  '23514',
  'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.',
  '만 14세에서 하루 부족하면 서버가 거부한다'
);

SELECT * FROM finish();
ROLLBACK;
