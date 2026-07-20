-- Reject ineligible signups before GoTrue inserts auth.users.
--
-- Email signup sends a self-declared birth date in user_metadata. This hook is
-- the server boundary that validates it; user_metadata is never used later for
-- RLS or authorization. Standard Google OAuth cannot carry this app field, so
-- new Google users are temporarily rejected while existing Google identities
-- continue to sign in (the hook only runs when a user would be created).

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
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message',
          'GOOGLE_SIGNUP_DISABLED: 신규 가입은 이메일로 진행해 주세요.'
      )
    );
  end if;

  if provider <> 'email' then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message',
          'SIGNUP_PROVIDER_NOT_ALLOWED: 현재 이메일 가입만 지원합니다.'
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
  from public, anon, authenticated;
grant execute on function public.before_user_created_allround(jsonb)
  to supabase_auth_admin;

-- Copy the already-validated email signup value into the application profile.
-- Direct fixture/admin inserts may omit it for intentionally incomplete legacy
-- accounts, but malformed non-empty values are rejected instead of silently
-- becoming an unverified profile.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  raw_birth_date text := nullif(
    btrim(new.raw_user_meta_data ->> 'birth_date'),
    ''
  );
  parsed_birth_date date;
begin
  if raw_birth_date is not null then
    begin
      parsed_birth_date := raw_birth_date::date;
    exception
      when invalid_datetime_format
        or datetime_field_overflow
        or invalid_text_representation then
        raise exception using
          errcode = 'check_violation',
          message = 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.';
    end;
  end if;

  insert into public.users (id, email, name, birth_date)
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      split_part(new.email, '@', 1)
    ),
    parsed_birth_date
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;
