BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(13);

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

-- user_sports 직접 DML 은 #320 이후 권한 자체가 없다(RPC 가 유일한 쓰기 경계).
-- 연령 게이트는 RLS 가 아니라 save_user_sports 본문이 건다 — DEFINER 라 RLS 를 우회하므로.
SELECT throws_ok(
  $$INSERT INTO public.user_sports (user_id, sport, grade, is_primary)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      'futsal',
      'intro',
      true
    )$$,
  '42501',
  'permission denied for table user_sports',
  '앱 클라이언트는 종목을 직접 INSERT 할 수 없다(RPC 전용 경계)'
);

SELECT throws_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"intro","is_primary":true}]'::jsonb)$$,
  '42501',
  '연령 검증이 필요합니다',
  '생년월일이 없는 계정은 종목을 등록할 수 없다'
);

-- 게이트 도입(2026-07-18) 전 가입해 birth_date 가 비어 있는데 종목은 가진 계정이 있다
-- (운영 실측 3명). RLS 시절 delete 는 연령을 보지 않았으므로, 줄이기만 하는 저장은
-- 계속 통과해야 한다 — 전체 삭제만 되고 부분 삭제가 막히면 되돌릴 수 없는 유실이 된다.
RESET ROLE;
INSERT INTO public.user_sports (user_id, sport, grade, is_primary) VALUES
  ('00000000-0000-4000-8000-000000000008', 'futsal', 'intro', true),
  ('00000000-0000-4000-8000-000000000008', 'tennis', 'y1to3', false);
SET LOCAL ROLE authenticated;

SELECT lives_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"intro","is_primary":true}]'::jsonb)$$,
  '연령 미검증이어도 기존 종목을 줄이기만 하는 저장은 통과한다'
);

SELECT throws_ok(
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"beginner","is_primary":true}]'::jsonb)$$,
  '42501',
  '연령 검증이 필요합니다',
  '연령 미검증 계정은 기존 종목의 등급을 바꿀 수 없다'
);

RESET ROLE;
DELETE FROM public.user_sports
 WHERE user_id = '00000000-0000-4000-8000-000000000008';
SET LOCAL ROLE authenticated;

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
  $$SELECT public.save_user_sports(
      '[{"sport":"futsal","grade":"intro","is_primary":true}]'::jsonb)$$,
  '연령 검증을 마친 계정은 종목을 등록할 수 있다'
);

SELECT throws_ok(
  $$INSERT INTO public.chat_messages
      (user_id, conversation_id, role, content)
    VALUES (
      '00000000-0000-4000-8000-000000000008',
      gen_random_uuid(),
      'user',
      '연령 검증 후 메시지'
    )$$,
  '42501',
  'new row violates row-level security policy for table "chat_messages"',
  '연령 검증 후에도 앱 클라이언트가 AI 대화를 직접 위조할 수 없다'
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
