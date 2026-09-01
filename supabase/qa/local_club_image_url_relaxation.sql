-- 로컬 스택 전용: 클럽/프로필 사진 URL 제약에 로컬 호스트를 추가한다.
--
-- ⚠️ 프로덕션에서 절대 실행하지 말 것. 반드시
--    bash scripts/qa/apply_local_image_url_relaxation.sh
-- 로 실행한다 — 그 래퍼가 로컬 스택인지 먼저 확인한다.
--
-- 왜 필요한가: clubs/club_posts/users 의 사진 URL CHECK 는 프로덕션 호스트만 허용한다.
-- 로컬 스택에 붙여 앱을 돌리면(app/.env.local.example) 업로드 URL 이
-- 127.0.0.1:54321 로 나와 저장이 막힌다.
--
-- 왜 seed.sql 이 아닌가: `supabase db push --include-seed` 로 seed 가 원격에 적용될 수
-- 있어, 로컬 완화가 프로덕션 제약을 덮어쓸 수 있다(codex MAJOR).
--
-- 되돌리기: supabase db reset (마이그레이션의 엄격한 정의로 돌아간다).

create or replace function public.club_image_urls_are_app_storage(
  p_urls text[],
  p_bucket text
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    bool_and(
      u is not null
      and u ~ (
        '^(https://bsjdgwmveokanclqwtvx\.supabase\.co'
        || '|http://(127\.0\.0\.1|localhost):54321)'
        || '/storage/v1/object/public/'
        || p_bucket
        || '/([0-9a-f-]{36}/)?[0-9a-f]{48}\.(jpg|png)$'
      )
    ),
    true
  )
  from unnest(p_urls) as u;
$$;

create or replace function public.user_avatar_url_is_app_storage(p_url text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select p_url is null or p_url ~ (
    '^(https://bsjdgwmveokanclqwtvx\.supabase\.co'
    || '|http://(127\.0\.0\.1|localhost):54321)'
    || '/storage/v1/object/public/profile-avatars/'
    || '[0-9a-f-]{36}/avatar\.(jpg|png)(\?v=[0-9]+)?$'
  );
$$;
