BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(8);

SELECT isnt(
  has_function_privilege('anon', 'public.enforce_ugc_text_policy()', 'EXECUTE'),
  true,
  'anon은 UGC 정책 트리거 함수를 직접 실행할 수 없다'
);

SELECT isnt(
  has_function_privilege('authenticated', 'public.enforce_ugc_text_policy()', 'EXECUTE'),
  true,
  '인증 사용자도 UGC 정책 트리거 함수를 직접 실행할 수 없다'
);

SELECT isnt(
  case
    when to_regprocedure('public.guard_tournament_format_columns()') is null then false
    else has_function_privilege(
      'anon',
      'public.guard_tournament_format_columns()',
      'EXECUTE'
    )
  end,
  true,
  'anon은 대회 정형화 보호 트리거 함수를 직접 실행할 수 없다'
);

SELECT isnt(
  case
    when to_regprocedure('public.guard_tournament_format_columns()') is null then false
    else has_function_privilege(
      'authenticated',
      'public.guard_tournament_format_columns()',
      'EXECUTE'
    )
  end,
  true,
  '인증 사용자도 대회 정형화 보호 트리거 함수를 직접 실행할 수 없다'
);

SELECT isnt(
  has_function_privilege('anon', 'public.respond_club_event(uuid, text)', 'EXECUTE'),
  true,
  'anon은 클럽 일정 응답 RPC를 실행할 수 없다'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.respond_club_event(uuid, text)', 'EXECUTE'),
  '인증 사용자는 클럽 일정 응답 RPC를 실행할 수 있다'
);

SELECT ok(
  has_function_privilege('service_role', 'public.enforce_ugc_text_policy()', 'EXECUTE'),
  'service role은 UGC 정책 트리거 함수 실행 권한을 유지한다'
);

SELECT ok(
  case
    when to_regprocedure('public.guard_tournament_format_columns()') is null then true
    else has_function_privilege(
      'service_role',
      'public.guard_tournament_format_columns()',
      'EXECUTE'
    )
  end,
  'service role은 대회 정형화 보호 트리거 함수 실행 권한을 유지한다'
);

SELECT * FROM finish();
ROLLBACK;
