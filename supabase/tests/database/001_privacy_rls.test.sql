BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(20);

-- fixture 존재 여부. runner가 persona seed를 생략하면 여기서 명확히 실패한다.
SELECT is(
  (SELECT count(*) FROM public.users WHERE email LIKE 'qa-%@allround.invalid'),
  8::bigint,
  '고정 QA 계정 8명이 준비되어 있다'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.users), 1::bigint,
  '일반 회원은 자신의 users 행만 조회한다');
SELECT is((SELECT count(*) FROM public.user_sports), 2::bigint,
  '일반 회원은 자신의 종목만 조회한다');
SELECT is((SELECT count(*) FROM public.user_tennis_orgs), 1::bigint,
  '일반 회원은 자신의 테니스 협회만 조회한다');
SELECT is((SELECT count(*) FROM public.tournament_favorites), 1::bigint,
  '일반 회원은 자신의 즐겨찾기만 조회한다');
SELECT is((SELECT count(*) FROM public.notifications), 1::bigint,
  '일반 회원은 자신의 알림만 조회한다');
SELECT is((SELECT count(*) FROM public.chat_messages), 1::bigint,
  '일반 회원은 자신의 AI 대화만 조회한다');
SELECT is((SELECT count(*) FROM public.user_blocks), 1::bigint,
  '차단자는 자신이 만든 차단만 조회한다');
SELECT is((SELECT count(*) FROM public.ugc_reports), 0::bigint,
  '신고자는 개인정보 snapshot이 포함된 신고 행을 직접 조회하지 못한다');
SELECT is((SELECT count(*) FROM public.user_penalties), 0::bigint,
  '일반 회원은 다른 사용자의 제재를 조회하지 못한다');

SELECT is_empty(
  $$UPDATE public.notifications
    SET is_read = true
    WHERE id = '00000000-0000-4000-8000-000000000402'
    RETURNING id$$,
  '다른 사용자의 알림을 읽음 처리할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.chat_messages
      (user_id, conversation_id, role, content)
    VALUES
      ('00000000-0000-4000-8000-000000000006', gen_random_uuid(), 'user', '침해 시도')$$,
  '42501',
  'new row violates row-level security policy for table "chat_messages"',
  '다른 사용자의 AI 대화를 작성할 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.tournament_favorites (user_id, tournament_id)
    VALUES
      ('00000000-0000-4000-8000-000000000006',
       '00000000-0000-4000-8000-000000000101')$$,
  '42501',
  'new row violates row-level security policy for table "tournament_favorites"',
  '다른 사용자의 즐겨찾기를 만들 수 없다'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000007', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000007","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.user_blocks), 0::bigint,
  '차단당한 사용자는 누가 자신을 차단했는지 조회하지 못한다');
SELECT is((SELECT count(*) FROM public.user_penalties), 1::bigint,
  '제재 대상은 자신의 활성 제재만 조회한다');

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

SELECT is((SELECT count(*) FROM public.users WHERE email LIKE 'qa-%@allround.invalid'), 8::bigint,
  '관리자는 전체 QA 사용자 행을 조회한다');
SELECT is((SELECT count(*) FROM public.notifications WHERE id IN (
  '00000000-0000-4000-8000-000000000401',
  '00000000-0000-4000-8000-000000000402'
)), 2::bigint, '관리자는 신고 대응에 필요한 알림을 조회한다');
SELECT is((SELECT count(*) FROM public.chat_messages WHERE id IN (
  '00000000-0000-4000-8000-000000000501',
  '00000000-0000-4000-8000-000000000502'
)), 2::bigint, '관리자는 정책상 허용된 AI 대화 감사 범위를 조회한다');
SELECT is((SELECT count(*) FROM public.ugc_reports), 1::bigint,
  '관리자는 신고 snapshot을 조회한다');
SELECT is((SELECT count(*) FROM public.user_penalties), 1::bigint,
  '관리자는 제재 내역을 조회한다');

SELECT * FROM finish();
ROLLBACK;
