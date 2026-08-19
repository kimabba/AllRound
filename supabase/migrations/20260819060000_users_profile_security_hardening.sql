-- users 셀프서비스 표면 보안 강화 (보안 점검 3번 항목 1~3).
-- 실명/닉네임 길이 제한, 아바타 URL을 우리 스토리지 주소로 고정,
-- 약관동의 컬럼 직접 쓰기 차단, 닉네임 금칙어 필터를 한 마이그레이션으로 묶는다.
-- (업로드 개수 제한은 성격이 달라 별도 마이그레이션 20260819070000으로 분리)
--
-- 설계 검토: backend-architect(Fable). 검토가 잡은 블로커 2건 반영:
--  - 가입 경로(handle_new_user, ensure_profile)가 30자 넘는 display_name/이메일
--    로컬파트를 그대로 넣으면 새 CHECK로 가입 자체가 막히므로 먼저 clamp한다.
--  - enforce_ugc_text_policy()는 여러 테이블이 공유하는 함수라 NEW.<field>를
--    쓰면 그 컬럼이 없는 테이블(club_posts 등)의 UGC 쓰기가 전부
--    'record "new" has no field ...'로 깨진다. 반드시 v_row->>'<field>'로 접근.

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 0) 가입 경로 name 클램프 (CHECK 추가 전에 먼저 — 순서 중요)
--    handle_new_user/ensure_profile 두 경로가 같은 클램프 규칙을 쓰므로
--    한 곳(clamp_display_name)에만 두고 공유한다 — 나중에 30자 상한이나
--    폴백 순서가 바뀔 때 한쪽만 고치고 넘어가면 이 마이그레이션이 막으려던
--    바로 그 버그(가입 경로가 CHECK보다 긴 name을 넣어 가입 자체가 막힘)가
--    재발한다(/code-review 지적).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.clamp_display_name(p_display_name text, p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT left(
    coalesce(
      nullif(btrim(p_display_name), ''),
      nullif(btrim(split_part(p_email, '@', 1)), ''),
      '사용자'
    ),
    30
  );
$$;

REVOKE ALL ON FUNCTION public.clamp_display_name(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.clamp_display_name(text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  raw_birth_date text := nullif(
    btrim(new.raw_user_meta_data ->> 'birth_date'),
    ''
  );
  parsed_birth_date date;
  clamped_name text := public.clamp_display_name(
    new.raw_user_meta_data ->> 'display_name',
    new.email
  );
BEGIN
  IF raw_birth_date IS NOT NULL THEN
    BEGIN
      parsed_birth_date := raw_birth_date::date;
    EXCEPTION
      WHEN invalid_datetime_format
        OR datetime_field_overflow
        OR invalid_text_representation THEN
        RAISE EXCEPTION USING
          errcode = 'check_violation',
          message = 'INVALID_BIRTH_DATE: 올바른 생년월일을 입력해 주세요.';
    END;
  END IF;

  INSERT INTO public.users (id, email, name, birth_date)
  VALUES (
    new.id,
    new.email,
    clamped_name,
    parsed_birth_date
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name)
  SELECT
    auth.uid(),
    email,
    public.clamp_display_name(raw_user_meta_data ->> 'display_name', email)
  FROM auth.users
  WHERE id = auth.uid()
  ON CONFLICT (id) DO UPDATE
    SET
      email = EXCLUDED.email,
      name = COALESCE(NULLIF(public.users.name, ''), EXCLUDED.name);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- 1) CHECK 제약: 실명/닉네임 길이, 아바타 URL 도메인 화이트리스트
--    (프로덕션 실측 2026-08-19: 30행 전원 통과, NOT VALID 불필요)
--    길이는 btrim(name)이 아니라 저장되는 값 그대로(name)를 잰다 — btrim된
--    길이만 재면 앞뒤 공백을 잔뜩 채워 실제 저장 길이를 무제한으로 늘릴 수
--    있다(예: 공백 5000자 + 글자 1개 → btrim 길이는 1이라 통과하지만 저장은
--    5001자, /code-review 지적).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.users
  ADD CONSTRAINT users_name_length
  CHECK (char_length(name) BETWEEN 1 AND 30);

ALTER TABLE public.users
  ADD CONSTRAINT users_nickname_length
  CHECK (nickname IS NULL OR char_length(nickname) BETWEEN 1 AND 20);

CREATE OR REPLACE FUNCTION public.user_avatar_url_is_app_storage(p_url text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
  SELECT p_url IS NULL OR p_url ~ (
    '^https://bsjdgwmveokanclqwtvx\.supabase\.co/storage/v1/object/public/profile-avatars/'
    || '[0-9a-f-]{36}/avatar\.(jpg|png)(\?v=[0-9]+)?$'
  );
$$;

COMMENT ON FUNCTION public.user_avatar_url_is_app_storage(text) IS
  'CHECK 제약 전용: avatar_url이 profile-avatars 버킷의 고정 경로({uid}/avatar.{jpg,png})만 가리키는지 검증한다. '
  '로컬 스택 완화는 supabase/qa/local_club_image_url_relaxation.sql 참고. '
  'CHECK는 소유자가 아니라 호출자(authenticated) 권한으로 평가되므로 EXECUTE grant가 필요하다.';

REVOKE ALL ON FUNCTION public.user_avatar_url_is_app_storage(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_avatar_url_is_app_storage(text)
  TO authenticated, service_role;

ALTER TABLE public.users
  ADD CONSTRAINT users_avatar_url_is_app_storage
  CHECK (public.user_avatar_url_is_app_storage(avatar_url));

-- ═══════════════════════════════════════════════════════════════
-- 2) 약관 동의 컬럼(ugc_terms_version/ugc_terms_accepted_at) 직접 쓰기 차단.
--    accept_current_ugc_terms() RPC만 이 컬럼을 쓸 수 있게 하고, PostgREST로
--    직접 UPDATE해 약관 화면을 안 보고 동의 기록을 만드는 경로를 막는다.
--    current_user='authenticated'로 한정해 마이그레이션(postgres)·service_role·
--    SECURITY DEFINER RPC(호출 중 current_user가 함수 소유자로 바뀜) 경로는
--    막지 않는다 — 이 가드만으로도 충분하지만, GUC는 "명시적 opt-in" 증거로 겸용.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.accept_current_ugc_terms()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  PERFORM set_config('app.ugc_terms_write_allowed', 'true', true);

  UPDATE public.users
  SET ugc_terms_version = '2026-07-15',
      ugc_terms_accepted_at = now()
  WHERE id = (SELECT auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_ugc_terms_self_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (old.ugc_terms_version IS DISTINCT FROM new.ugc_terms_version
      OR old.ugc_terms_accepted_at IS DISTINCT FROM new.ugc_terms_accepted_at)
     AND current_user = 'authenticated'
     AND coalesce(current_setting('app.ugc_terms_write_allowed', true), '') <> 'true'
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'ugc_terms 컬럼은 accept_current_ugc_terms() RPC로만 변경할 수 있습니다';
  END IF;
  RETURN new;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_ugc_terms_self_update()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prevent_ugc_terms_self_update()
  TO service_role;

DROP TRIGGER IF EXISTS users_prevent_ugc_terms_self_update ON public.users;
CREATE TRIGGER users_prevent_ugc_terms_self_update
  BEFORE UPDATE OF ugc_terms_version, ugc_terms_accepted_at ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ugc_terms_self_update();

-- ═══════════════════════════════════════════════════════════════
-- 3) 닉네임 금칙어 필터. enforce_ugc_text_policy()는 clubs/club_posts 등과
--    공유하는 함수이므로 NEW.nickname이 아니라 v_row->>'nickname'으로 접근한다.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enforce_ugc_text_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- to_jsonb(NEW)로 접근한다. PL/pgSQL simple CASE는 매칭되지 않는 분기의
  -- NEW.<field> 참조까지 트리거 테이블 row 타입으로 resolve하므로, 여러 테이블이
  -- 공유하는 이 함수에서 NEW.field를 직접 쓰면 'record new has no field ...' 로
  -- 모든 UGC 쓰기가 실패한다. jsonb ->> 는 없는 필드에 NULL을 돌려줘 안전하다.
  v_row jsonb := to_jsonb(NEW);
  v_text text;
  v_normalized text;
  v_term text;
BEGIN
  v_text := CASE TG_TABLE_NAME
    WHEN 'club_posts' THEN concat_ws(' ', v_row->>'title', v_row->>'body')
    WHEN 'club_post_comments' THEN v_row->>'body'
    WHEN 'club_events' THEN concat_ws(' ', v_row->>'title', v_row->>'description', v_row->>'location_text')
    WHEN 'clubs' THEN concat_ws(' ', v_row->>'name', v_row->>'description', v_row->>'contact')
    WHEN 'club_join_requests' THEN COALESCE(v_row->>'message', '')
    WHEN 'club_recruiting_posts' THEN concat_ws(' ',
      v_row->>'title', v_row->>'intro', v_row->>'place', v_row->>'schedule_text', v_row->>'position_text', v_row->>'cost_text')
    WHEN 'users' THEN COALESCE(v_row->>'nickname', '')
    ELSE ''
  END;
  v_normalized := regexp_replace(lower(v_text), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g');

  SELECT regexp_replace(lower(t.term), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g')
  INTO v_term
  FROM public.ugc_moderation_terms t
  WHERE t.active
    AND v_normalized LIKE '%' || regexp_replace(
      lower(t.term), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g'
    ) || '%'
  LIMIT 1;

  IF v_term IS NOT NULL THEN
    RAISE EXCEPTION 'UGC_CONTENT_BLOCKED';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_text, 'https?://', 'gi')) > 2 THEN
    RAISE EXCEPTION 'UGC_SPAM_BLOCKED';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_ugc_filter ON public.users;
CREATE TRIGGER users_ugc_filter
  BEFORE INSERT OR UPDATE OF nickname ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();

COMMIT;
