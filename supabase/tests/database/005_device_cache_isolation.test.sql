BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(18);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT lives_ok(
  $$SELECT public.bind_my_device_token(
      'qa-shared-device-token-123456789',
      'ios'::public.device_platform
    )$$,
  '계정 A가 합성 기기 토큰을 등록할 수 있다'
);

SELECT is(
  (SELECT count(*) FROM public.device_tokens
   WHERE token = 'qa-shared-device-token-123456789'),
  1::bigint,
  '계정 A에는 합성 기기 토큰이 한 건만 보인다'
);

SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000006', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

SELECT lives_ok(
  $$SELECT public.bind_my_device_token(
      'qa-shared-device-token-123456789',
      'ios'::public.device_platform
    )$$,
  '계정 B가 같은 물리 기기 토큰을 재등록할 수 있다'
);

SELECT is(
  (SELECT count(*) FROM public.device_tokens
   WHERE token = 'qa-shared-device-token-123456789'),
  1::bigint,
  '토큰 재등록 뒤 계정 B에도 한 건만 보인다'
);

SELECT is(
  (SELECT user_id FROM public.device_tokens
   WHERE token = 'qa-shared-device-token-123456789'),
  '00000000-0000-4000-8000-000000000006'::uuid,
  '같은 기기 토큰의 소유자는 계정 B로 원자적으로 이전된다'
);

SELECT lives_ok(
  $$SELECT public.unbind_my_device_tokens()$$,
  '계정 B가 로그아웃 전에 자신의 기기 토큰을 해제할 수 있다'
);

SELECT is(
  (SELECT count(*) FROM public.device_tokens
   WHERE token = 'qa-shared-device-token-123456789'),
  0::bigint,
  '로그아웃 토큰 해제 뒤 계정 B에는 해당 토큰이 남지 않는다'
);

SELECT is(
  (SELECT count(*) FROM public.qa_cache),
  0::bigint,
  '인증 사용자는 AI 의미 캐시를 직접 조회할 수 없다'
);

RESET ROLE;

SELECT is(
  (SELECT count(*) FROM public.device_tokens
   WHERE token = 'qa-shared-device-token-123456789'),
  0::bigint,
  '관리자 관점에서도 해제한 합성 기기 토큰은 완전히 삭제됐다'
);

SET LOCAL ROLE service_role;

SELECT lives_ok(
  $$SELECT public.qa_cache_insert_if_absent(
      '00000000-0000-4000-8000-000000000005'::uuid,
      '같은 질문',
      array_fill(1::real, ARRAY[768])::vector(768),
      '계정 A 전용 답변',
      '[]'::jsonb,
      'shared-context',
      now() + interval '1 hour'
    )$$,
  '서비스 역할이 계정 A 전용 캐시를 저장할 수 있다'
);

SELECT lives_ok(
  $$SELECT public.qa_cache_insert_if_absent(
      '00000000-0000-4000-8000-000000000006'::uuid,
      '같은 질문',
      array_fill(1::real, ARRAY[768])::vector(768),
      '계정 B 전용 답변',
      '[]'::jsonb,
      'shared-context',
      now() + interval '1 hour'
    )$$,
  '같은 질문과 문맥도 계정 B 캐시로 별도 저장할 수 있다'
);

SELECT is(
  (SELECT count(*) FROM public.qa_cache
   WHERE question_text = '같은 질문'
     AND user_context_hash = 'shared-context'),
  2::bigint,
  '동일 질문 캐시는 사용자별로 두 행에 격리된다'
);

SELECT is(
  (SELECT answer_text
   FROM public.qa_cache_lookup(
     array_fill(1::real, ARRAY[768])::vector(768),
     '00000000-0000-4000-8000-000000000005'::uuid,
     'shared-context',
     0.92
   )),
  '계정 A 전용 답변'::text,
  '계정 A 조회에는 계정 A 캐시만 반환된다'
);

SELECT is(
  (SELECT answer_text
   FROM public.qa_cache_lookup(
     array_fill(1::real, ARRAY[768])::vector(768),
     '00000000-0000-4000-8000-000000000006'::uuid,
     'shared-context',
     0.92
   )),
  '계정 B 전용 답변'::text,
  '계정 B 조회에는 계정 B 캐시만 반환된다'
);

SELECT lives_ok(
  $$SELECT public.qa_cache_insert_if_absent(
      '00000000-0000-4000-8000-000000000005'::uuid,
      '만료된 질문',
      array_fill(1::real, ARRAY[768])::vector(768),
      '만료된 답변',
      '[]'::jsonb,
      'expired-context',
      now() - interval '1 minute'
    )$$,
  '만료 경계 검사용 캐시를 저장할 수 있다'
);

SELECT is_empty(
  $$SELECT answer_text
    FROM public.qa_cache_lookup(
      array_fill(1::real, ARRAY[768])::vector(768),
      '00000000-0000-4000-8000-000000000005'::uuid,
      'expired-context',
      0.92
    )$$,
  'TTL이 지난 캐시는 조회 결과에서 제외된다'
);

RESET ROLE;

SELECT is(
  (SELECT count(*)
   FROM pg_indexes
   WHERE schemaname = 'public'
     AND indexname = 'qa_cache_unique_question_per_user_context'
     AND indexdef LIKE '%owner_user_id%'),
  1::bigint,
  'AI 캐시 중복 방지 인덱스도 사용자 ID를 포함한다'
);

SELECT is(
  (SELECT count(*)
   FROM cron.job
   WHERE jobname = 'qa-cache-expired-cleanup'),
  1::bigint,
  '만료된 AI 캐시를 실제 삭제하는 일일 작업이 등록돼 있다'
);

SELECT * FROM finish();
ROLLBACK;
