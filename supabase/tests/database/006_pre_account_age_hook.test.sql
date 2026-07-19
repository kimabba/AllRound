BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(8);

SELECT is(
  public.before_user_created_allround(
    jsonb_build_object(
      'user', jsonb_build_object(
        'app_metadata', jsonb_build_object('provider', 'email'),
        'user_metadata', jsonb_build_object(
          'birth_date',
          (current_date - interval '14 years')::date::text
        )
      )
    )
  ),
  '{}'::jsonb,
  '정확히 만 14세인 이메일 가입은 계정 생성 전에 허용한다'
);

SELECT is(
  public.before_user_created_allround(
    '{"user":{"app_metadata":{"provider":"email"},"user_metadata":{}}}'::jsonb
  ),
  jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 400,
      'message', 'BIRTH_DATE_REQUIRED: 계정 생성 전에 생년월일을 확인해 주세요.'
    )
  ),
  '생년월일이 없는 이메일 가입은 auth.users 생성 전에 거부한다'
);

SELECT is(
  public.before_user_created_allround(
    '{"user":{"app_metadata":{"provider":"email"},"user_metadata":{"birth_date":"not-a-date"}}}'::jsonb
  ),
  jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 400,
      'message', 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.'
    )
  ),
  '잘못된 생년월일 형식을 안전 오류로 거부한다'
);

SELECT is(
  public.before_user_created_allround(
    jsonb_build_object(
      'user', jsonb_build_object(
        'app_metadata', jsonb_build_object('provider', 'email'),
        'user_metadata', jsonb_build_object(
          'birth_date',
          ((current_date - interval '14 years') + interval '1 day')::date::text
        )
      )
    )
  ),
  jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.'
    )
  ),
  '만 14세에서 하루 부족한 이메일 가입은 auth.users 생성 전에 거부한다'
);

SELECT is(
  public.before_user_created_allround(
    '{"user":{"app_metadata":{"provider":"email"},"user_metadata":{"birth_date":"1899-12-31"}}}'::jsonb
  ),
  jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 400,
      'message', 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.'
    )
  ),
  '허용 범위보다 오래된 생년월일은 거부한다'
);

SELECT is(
  public.before_user_created_allround(
    '{"user":{"app_metadata":{"provider":"google"},"user_metadata":{}}}'::jsonb
  ),
  jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 403,
      'message', 'GOOGLE_SIGNUP_DISABLED: 신규 가입은 이메일로 진행해 주세요.'
    )
  ),
  '신규 Google 사용자는 검증된 생년월일 전달 경로가 생길 때까지 거부한다'
);

SELECT is(
  has_function_privilege(
    'authenticated',
    'public.before_user_created_allround(jsonb)',
    'EXECUTE'
  ),
  false,
  '앱 사용자는 가입 정책 훅을 직접 호출할 수 없다'
);

SELECT is(
  has_function_privilege(
    'supabase_auth_admin',
    'public.before_user_created_allround(jsonb)',
    'EXECUTE'
  ),
  true,
  'Supabase Auth만 가입 정책 훅을 실행할 수 있다'
);

SELECT * FROM finish();
ROLLBACK;
