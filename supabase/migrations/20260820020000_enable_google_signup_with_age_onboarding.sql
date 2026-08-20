-- Google OAuth 신규 사용자를 표준 가입 흐름으로 허용한다.
--
-- Google ID token에는 앱 전용 birth_date를 실을 수 없으므로 Google 계정은
-- auth.users + 빈 public.users profile을 먼저 만든다. 로그인 직후 Flutter
-- onboarding이 생년월일을 필수로 받고, public.enforce_min_signup_age 트리거와
-- public.has_verified_signup_age 기반 RLS/Edge guard가 검증 전 핵심 쓰기를 막는다.
-- 이메일 가입은 기존처럼 계정 생성 전에 birth_date를 검증한다.

create or replace function public.before_user_created_allround(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  provider text := lower(
    coalesce(event -> 'user' -> 'app_metadata' ->> 'provider', '')
  );
  raw_birth_date text := nullif(
    btrim(event -> 'user' -> 'user_metadata' ->> 'birth_date'),
    ''
  );
  parsed_birth_date date;
begin
  if provider = 'google' then
    return '{}'::jsonb;
  end if;

  if provider <> 'email' then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message',
          'SIGNUP_PROVIDER_NOT_ALLOWED: 현재 이메일과 Google 가입만 지원합니다.'
      )
    );
  end if;

  if raw_birth_date is null then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message',
          'BIRTH_DATE_REQUIRED: 계정 생성 전에 생년월일을 확인해 주세요.'
      )
    );
  end if;

  begin
    parsed_birth_date := raw_birth_date::date;
  exception
    when invalid_datetime_format
      or datetime_field_overflow
      or invalid_text_representation then
      return jsonb_build_object(
        'error', jsonb_build_object(
          'http_code', 400,
          'message', 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.'
        )
      );
  end;

  if parsed_birth_date < date '1900-01-01'
     or parsed_birth_date > current_date then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.'
      )
    );
  end if;

  if parsed_birth_date > (current_date - interval '14 years')::date then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message', 'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.'
      )
    );
  end if;

  return '{}'::jsonb;
end;
$function$;

revoke all on function public.before_user_created_allround(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.before_user_created_allround(jsonb)
  to supabase_auth_admin;
