-- JY-115: UGC 신고·사용자 차단·운영 제재·명시적 약관 동의
-- 신고 원문은 서버가 snapshot 으로 보존하며, 증거 이미지는 private bucket 에 저장한다.

BEGIN;

CREATE TYPE public.ugc_target_type AS ENUM (
  'club_post',
  'club_comment',
  'club_event',
  'club',
  'user',
  'ai_message'
);

CREATE TYPE public.ugc_report_reason AS ENUM (
  'abusive_language',
  'spam',
  'harassment',
  'sexual_content',
  'hate',
  'violence',
  'privacy',
  'other'
);

CREATE TYPE public.ugc_report_status AS ENUM (
  'pending',
  'reviewing',
  'actioned',
  'dismissed'
);

CREATE TYPE public.ugc_penalty_type AS ENUM (
  'comment_restriction',
  'club_join_restriction',
  'community_restriction'
);

ALTER TABLE public.users
  ADD COLUMN ugc_terms_version text,
  ADD COLUMN ugc_terms_accepted_at timestamptz;

CREATE TABLE public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_blocks_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX user_blocks_blocked_idx
  ON public.user_blocks (blocked_id, blocker_id);

CREATE TABLE public.ugc_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reported_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  target_type public.ugc_target_type NOT NULL,
  target_id uuid NOT NULL,
  reason public.ugc_report_reason NOT NULL,
  details text,
  evidence_paths text[] NOT NULL DEFAULT '{}',
  content_snapshot jsonb NOT NULL,
  status public.ugc_report_status NOT NULL DEFAULT 'pending',
  reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  resolution_note text,
  content_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ugc_reports_details_length
    CHECK (details IS NULL OR length(details) BETWEEN 1 AND 1000),
  CONSTRAINT ugc_reports_evidence_count
    CHECK (cardinality(evidence_paths) <= 3),
  CONSTRAINT ugc_reports_resolution_length
    CHECK (resolution_note IS NULL OR length(resolution_note) BETWEEN 1 AND 2000)
);

CREATE INDEX ugc_reports_status_created_idx
  ON public.ugc_reports (status, created_at DESC);
CREATE INDEX ugc_reports_reported_user_idx
  ON public.ugc_reports (reported_user_id, created_at DESC);
CREATE UNIQUE INDEX ugc_reports_one_open_per_target_idx
  ON public.ugc_reports (reporter_id, target_type, target_id)
  WHERE status IN ('pending', 'reviewing');

CREATE TRIGGER ugc_reports_touch_updated_at
  BEFORE UPDATE ON public.ugc_reports
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TABLE public.user_penalties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  penalty_type public.ugc_penalty_type NOT NULL,
  report_id uuid REFERENCES public.ugc_reports(id) ON DELETE SET NULL,
  reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 1000),
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  created_by uuid NOT NULL REFERENCES public.users(id),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES public.users(id),
  revoke_reason text CHECK (
    revoke_reason IS NULL OR length(revoke_reason) BETWEEN 1 AND 1000
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_penalties_valid_period
    CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE INDEX user_penalties_active_user_idx
  ON public.user_penalties (user_id, penalty_type, ends_at)
  WHERE revoked_at IS NULL;

CREATE TABLE public.ugc_moderation_terms (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  term text NOT NULL UNIQUE CHECK (length(btrim(term)) BETWEEN 2 AND 100),
  category text NOT NULL CHECK (category IN ('abuse', 'hate', 'sexual', 'spam')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 최소 출시 필터. 운영자는 테이블에서 용어를 추가·비활성화할 수 있다.
INSERT INTO public.ugc_moderation_terms (term, category) VALUES
  ('씨발', 'abuse'),
  ('시발', 'abuse'),
  ('개새끼', 'abuse'),
  ('병신', 'abuse'),
  ('ㅅㅂ', 'abuse'),
  ('ㅂㅅ', 'abuse');

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ugc_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_penalties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ugc_moderation_terms ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_blocks_self_select ON public.user_blocks
  FOR SELECT USING (blocker_id = (SELECT auth.uid()));
CREATE POLICY user_blocks_self_insert ON public.user_blocks
  FOR INSERT WITH CHECK (blocker_id = (SELECT auth.uid()));
CREATE POLICY user_blocks_self_delete ON public.user_blocks
  FOR DELETE USING (blocker_id = (SELECT auth.uid()));
CREATE POLICY user_blocks_admin_all ON public.user_blocks
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 신고 조회는 admin(모더레이션 화면)만 허용한다. 신고자 본인 조회 정책을 두지 않는다:
-- content_snapshot에 제3자 댓글·미공개 클럽 연락처·신고 대상 실명이 담기므로,
-- 신고자에게 노출되면 개인정보 최소수집(§21) 위반이 된다. 신고 생성은 create_ugc_report
-- RPC(security definer)로만 이뤄지고, 신고자용 조회 UI는 없다.
CREATE POLICY ugc_reports_admin_all ON public.ugc_reports
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY user_penalties_self_select ON public.user_penalties
  FOR SELECT USING (user_id = (SELECT auth.uid()));
CREATE POLICY user_penalties_admin_all ON public.user_penalties
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY ugc_moderation_terms_admin_all ON public.ugc_moderation_terms
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.has_accepted_current_ugc_terms()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = (SELECT auth.uid())
      AND u.ugc_terms_version = '2026-07-15'
      AND u.ugc_terms_accepted_at IS NOT NULL
  );
$$;

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

  UPDATE public.users
  SET ugc_terms_version = '2026-07-15',
      ugc_terms_accepted_at = now()
  WHERE id = (SELECT auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.has_active_ugc_penalty(
  p_penalty_types public.ugc_penalty_type[]
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_penalties p
    WHERE p.user_id = (SELECT auth.uid())
      AND p.penalty_type = ANY(p_penalty_types)
      AND p.revoked_at IS NULL
      AND p.starts_at <= now()
      AND (p.ends_at IS NULL OR p.ends_at > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.my_ugc_access()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'terms_accepted', public.has_accepted_current_ugc_terms(),
    'terms_version', '2026-07-15',
    'penalties', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'type', p.penalty_type,
        'ends_at', p.ends_at,
        'reason', p.reason
      ) ORDER BY p.created_at DESC)
      FROM public.user_penalties p
      WHERE p.user_id = (SELECT auth.uid())
        AND p.revoked_at IS NULL
        AND p.starts_at <= now()
        AND (p.ends_at IS NULL OR p.ends_at > now())
    ), '[]'::jsonb)
  );
$$;

CREATE OR REPLACE FUNCTION public.is_user_blocked_pair(p_other_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT p_other_user_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.user_blocks b
    WHERE (
      b.blocker_id = (SELECT auth.uid())
      AND b.blocked_id = p_other_user_id
    ) OR (
      b.blocker_id = p_other_user_id
      AND b.blocked_id = (SELECT auth.uid())
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.is_commentable_club_post(p_post_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.club_posts p
    JOIN public.club_members m ON m.club_id = p.club_id
    WHERE p.id = p_post_id
      AND p.tag IN ('free', 'recruit', 'photo')
      AND m.user_id = (SELECT auth.uid())
      AND m.status = 'active'
      AND NOT public.is_user_blocked_pair(p.author_id)
  );
$$;

CREATE OR REPLACE FUNCTION public.block_user(p_blocked_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF p_blocked_user_id = (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'CANNOT_BLOCK_SELF';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_blocked_user_id) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  INSERT INTO public.user_blocks (blocker_id, blocked_id)
  VALUES ((SELECT auth.uid()), p_blocked_user_id)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_blocked_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM public.user_blocks
  WHERE blocker_id = (SELECT auth.uid())
    AND blocked_id = p_blocked_user_id;
$$;

CREATE OR REPLACE FUNCTION public.my_blocked_users()
RETURNS TABLE (
  user_id uuid,
  display_name text,
  blocked_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    u.id,
    COALESCE(NULLIF(btrim(u.nickname), ''), NULLIF(btrim(u.name), ''), '사용자'),
    b.created_at
  FROM public.user_blocks b
  JOIN public.users u ON u.id = b.blocked_id
  WHERE b.blocker_id = (SELECT auth.uid())
  ORDER BY b.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.create_ugc_report(
  p_target_type public.ugc_target_type,
  p_target_id uuid,
  p_reason public.ugc_report_reason,
  p_details text DEFAULT NULL,
  p_evidence_paths text[] DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reporter_id uuid := (SELECT auth.uid());
  v_reported_user_id uuid;
  v_snapshot jsonb;
  v_club_id uuid;
  v_path text;
  v_report_id uuid;
BEGIN
  IF v_reporter_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF p_details IS NOT NULL AND length(btrim(p_details)) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_REPORT_DETAILS';
  END IF;
  IF cardinality(COALESCE(p_evidence_paths, '{}')) > 3 THEN
    RAISE EXCEPTION 'TOO_MANY_EVIDENCE_FILES';
  END IF;
  FOREACH v_path IN ARRAY COALESCE(p_evidence_paths, '{}') LOOP
    IF v_path !~ ('^' || v_reporter_id::text || '/[A-Za-z0-9._/-]+$')
       OR v_path LIKE '%..%' THEN
      RAISE EXCEPTION 'INVALID_EVIDENCE_PATH';
    END IF;
  END LOOP;
  IF (
    SELECT count(*)
    FROM public.ugc_reports
    WHERE reporter_id = v_reporter_id
      AND created_at > now() - interval '1 day'
  ) >= 20 THEN
    RAISE EXCEPTION 'REPORT_RATE_LIMITED';
  END IF;

  CASE p_target_type
    WHEN 'club_post' THEN
      SELECT p.author_id, p.club_id,
        jsonb_build_object(
          'post_id', p.id,
          'club_id', p.club_id,
          'tag', p.tag,
          'title', p.title,
          'body', p.body,
          'image_urls', p.image_urls,
          'created_at', p.created_at
        )
      INTO v_reported_user_id, v_club_id, v_snapshot
      FROM public.club_posts p
      WHERE p.id = p_target_id;

    WHEN 'club_comment' THEN
      SELECT c.author_id, p.club_id,
        jsonb_build_object(
          'comment_id', c.id,
          'comment_body', c.body,
          'comment_created_at', c.created_at,
          'post_id', p.id,
          'post_title', p.title,
          'post_body', p.body,
          'context_comments', COALESCE((
            SELECT jsonb_agg(to_jsonb(context_rows) ORDER BY context_rows.created_at)
            FROM (
              SELECT cc.id, cc.author_id, cc.body, cc.created_at
              FROM public.club_post_comments cc
              WHERE cc.post_id = p.id
              ORDER BY cc.created_at DESC
              LIMIT 20
            ) context_rows
          ), '[]'::jsonb)
        )
      INTO v_reported_user_id, v_club_id, v_snapshot
      FROM public.club_post_comments c
      JOIN public.club_posts p ON p.id = c.post_id
      WHERE c.id = p_target_id;

    WHEN 'club_event' THEN
      SELECT e.created_by, e.club_id,
        jsonb_build_object(
          'event_id', e.id,
          'club_id', e.club_id,
          'title', e.title,
          'description', e.description,
          'location_text', e.location_text,
          'starts_at', e.starts_at,
          'created_at', e.created_at
        )
      INTO v_reported_user_id, v_club_id, v_snapshot
      FROM public.club_events e
      WHERE e.id = p_target_id;

    WHEN 'club' THEN
      -- 클럽 엔티티 신고는 승인(공개) 클럽이거나 해당 클럽 멤버/관리자만 가능하다.
      -- 미공개(pending/rejected) 클럽의 연락처 등 개인정보 IDOR을 WHERE에서 차단하고,
      -- contact는 스냅샷에서 제외한다(admin은 clubs 테이블을 직접 조회).
      SELECT c.created_by,
        jsonb_build_object(
          'club_id', c.id,
          'name', c.name,
          'description', c.description,
          'logo_url', c.logo_url,
          'created_at', c.created_at
        )
      INTO v_reported_user_id, v_snapshot
      FROM public.clubs c
      WHERE c.id = p_target_id
        AND (
          c.status = 'approved'
          OR public.is_active_club_member(c.id)
          OR public.is_admin()
        );

    WHEN 'user' THEN
      SELECT u.id,
        jsonb_build_object(
          'user_id', u.id,
          'display_name', COALESCE(u.nickname, u.name)
        )
      INTO v_reported_user_id, v_snapshot
      FROM public.users u
      WHERE u.id = p_target_id;

    WHEN 'ai_message' THEN
      SELECT NULL::uuid,
        jsonb_build_object(
          'message_id', m.id,
          'conversation_id', m.conversation_id,
          'role', m.role,
          'content', m.content,
          'citations', m.citations,
          'created_at', m.created_at
        )
      INTO v_reported_user_id, v_snapshot
      FROM public.chat_messages m
      WHERE m.id = p_target_id
        AND m.user_id = v_reporter_id
        AND m.role = 'assistant';
  END CASE;

  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'REPORT_TARGET_NOT_FOUND';
  END IF;
  IF v_club_id IS NOT NULL
     AND NOT public.is_active_club_member(v_club_id)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'REPORT_TARGET_NOT_VISIBLE';
  END IF;
  IF v_reported_user_id = v_reporter_id THEN
    RAISE EXCEPTION 'CANNOT_REPORT_SELF';
  END IF;

  INSERT INTO public.ugc_reports (
    reporter_id,
    reported_user_id,
    target_type,
    target_id,
    reason,
    details,
    evidence_paths,
    content_snapshot
  ) VALUES (
    v_reporter_id,
    v_reported_user_id,
    p_target_type,
    p_target_id,
    p_reason,
    NULLIF(btrim(p_details), ''),
    COALESCE(p_evidence_paths, '{}'),
    v_snapshot
  )
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'REPORT_ALREADY_OPEN';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_resolve_ugc_report(
  p_report_id uuid,
  p_resolution text,
  p_delete_content boolean DEFAULT false,
  p_penalty_type public.ugc_penalty_type DEFAULT NULL,
  p_duration_days integer DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid := (SELECT auth.uid());
  v_report public.ugc_reports%ROWTYPE;
  v_penalty_id uuid;
  v_deleted boolean := false;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED';
  END IF;
  IF p_resolution NOT IN ('dismiss', 'action') THEN
    RAISE EXCEPTION 'INVALID_RESOLUTION';
  END IF;
  IF p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION 'INVALID_RESOLUTION_NOTE';
  END IF;
  IF p_penalty_type IS NOT NULL
     AND p_duration_days IS NOT NULL
     AND p_duration_days NOT BETWEEN 1 AND 3650 THEN
    RAISE EXCEPTION 'INVALID_PENALTY_DURATION';
  END IF;

  SELECT * INTO v_report
  FROM public.ugc_reports
  WHERE id = p_report_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REPORT_NOT_FOUND';
  END IF;
  IF v_report.status IN ('actioned', 'dismissed') THEN
    RAISE EXCEPTION 'REPORT_ALREADY_RESOLVED';
  END IF;

  IF p_delete_content AND p_resolution = 'action' THEN
    CASE v_report.target_type
      WHEN 'club_post' THEN
        DELETE FROM public.club_posts WHERE id = v_report.target_id;
        v_deleted := FOUND;
      WHEN 'club_comment' THEN
        DELETE FROM public.club_post_comments WHERE id = v_report.target_id;
        v_deleted := FOUND;
      WHEN 'club_event' THEN
        DELETE FROM public.club_events WHERE id = v_report.target_id;
        v_deleted := FOUND;
      ELSE
        v_deleted := false;
    END CASE;
  END IF;

  IF p_penalty_type IS NOT NULL AND p_resolution = 'action' THEN
    IF v_report.reported_user_id IS NULL THEN
      RAISE EXCEPTION 'REPORTED_USER_NOT_AVAILABLE';
    END IF;
    INSERT INTO public.user_penalties (
      user_id,
      penalty_type,
      report_id,
      reason,
      ends_at,
      created_by
    ) VALUES (
      v_report.reported_user_id,
      p_penalty_type,
      v_report.id,
      COALESCE(NULLIF(btrim(p_note), ''), '커뮤니티 운영정책 위반'),
      CASE
        WHEN p_duration_days IS NULL THEN NULL
        ELSE now() + make_interval(days => p_duration_days)
      END,
      v_admin_id
    )
    RETURNING id INTO v_penalty_id;
  END IF;

  UPDATE public.ugc_reports
  SET status = CASE
        WHEN p_resolution = 'dismiss' THEN 'dismissed'::public.ugc_report_status
        ELSE 'actioned'::public.ugc_report_status
      END,
      reviewed_by = v_admin_id,
      reviewed_at = now(),
      resolution_note = NULLIF(btrim(p_note), ''),
      content_deleted = v_deleted
  WHERE id = v_report.id;

  RETURN jsonb_build_object(
    'report_id', v_report.id,
    'content_deleted', v_deleted,
    'penalty_id', v_penalty_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_revoke_user_penalty(
  p_penalty_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'ADMIN_REQUIRED';
  END IF;
  IF length(btrim(p_reason)) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_REVOKE_REASON';
  END IF;

  UPDATE public.user_penalties
  SET revoked_at = now(),
      revoked_by = (SELECT auth.uid()),
      revoke_reason = btrim(p_reason)
  WHERE id = p_penalty_id
    AND revoked_at IS NULL;
END;
$$;

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

CREATE TRIGGER club_posts_ugc_filter
  BEFORE INSERT OR UPDATE OF title, body ON public.club_posts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();
CREATE TRIGGER club_post_comments_ugc_filter
  BEFORE INSERT OR UPDATE OF body ON public.club_post_comments
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();
CREATE TRIGGER club_events_ugc_filter
  BEFORE INSERT OR UPDATE OF title, description, location_text ON public.club_events
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();
CREATE TRIGGER clubs_ugc_filter
  BEFORE INSERT OR UPDATE OF name, description, contact ON public.clubs
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();
CREATE TRIGGER club_join_requests_ugc_filter
  BEFORE INSERT OR UPDATE OF message ON public.club_join_requests
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();
CREATE TRIGGER club_recruiting_posts_ugc_filter
  BEFORE INSERT OR UPDATE OF title, intro, place, schedule_text, position_text, cost_text
  ON public.club_recruiting_posts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_ugc_text_policy();

-- 차단한 사용자와 차단당한 사용자의 UGC는 서로 보이지 않는다.
DROP POLICY IF EXISTS club_posts_select ON public.club_posts;
CREATE POLICY club_posts_select ON public.club_posts
  FOR SELECT USING (
    public.is_admin()
    OR (
      public.is_active_club_member(club_id)
      AND NOT public.is_user_blocked_pair(author_id)
    )
  );

DROP POLICY IF EXISTS club_post_comments_select ON public.club_post_comments;
CREATE POLICY club_post_comments_select ON public.club_post_comments
  FOR SELECT USING (
    public.is_admin()
    OR (
      public.is_commentable_club_post(post_id)
      AND NOT public.is_user_blocked_pair(author_id)
    )
  );

DROP POLICY IF EXISTS club_events_select ON public.club_events;
CREATE POLICY club_events_select ON public.club_events
  FOR SELECT USING (
    public.is_admin()
    OR (
      public.is_active_club_member(club_id)
      AND NOT public.is_user_blocked_pair(created_by)
    )
  );

-- 약관 동의와 제재는 최종적으로 RLS 에서 강제한다.
DROP POLICY IF EXISTS club_posts_insert ON public.club_posts;
CREATE POLICY club_posts_insert ON public.club_posts
  FOR INSERT WITH CHECK (
    author_id = (SELECT auth.uid())
    AND public.has_accepted_current_ugc_terms()
    AND NOT public.has_active_ugc_penalty(
      ARRAY['community_restriction']::public.ugc_penalty_type[]
    )
    AND public.is_active_club_member(club_id)
    AND (
      tag <> 'notice'
      OR public.is_club_manager(club_id)
      OR EXISTS (
        SELECT 1 FROM public.club_members m
        WHERE m.club_id = club_posts.club_id
          AND m.user_id = (SELECT auth.uid())
          AND m.status = 'active'
          AND m.can_post_notice
      )
    )
    AND (NOT is_pinned OR public.is_club_manager(club_id) OR public.is_admin())
  );

DROP POLICY IF EXISTS club_posts_update ON public.club_posts;
CREATE POLICY club_posts_update ON public.club_posts
  FOR UPDATE USING (
    public.is_admin()
    OR (
      (author_id = (SELECT auth.uid()) OR public.is_club_manager(club_id))
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  ) WITH CHECK (
    public.is_admin()
    OR (
      (author_id = (SELECT auth.uid()) OR public.is_club_manager(club_id))
      AND public.is_active_club_member(club_id)
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  );

DROP POLICY IF EXISTS club_post_comments_insert ON public.club_post_comments;
CREATE POLICY club_post_comments_insert ON public.club_post_comments
  FOR INSERT WITH CHECK (
    author_id = (SELECT auth.uid())
    AND public.has_accepted_current_ugc_terms()
    AND NOT public.has_active_ugc_penalty(
      ARRAY[
        'comment_restriction',
        'community_restriction'
      ]::public.ugc_penalty_type[]
    )
    AND public.is_commentable_club_post(post_id)
  );

DROP POLICY IF EXISTS club_events_insert ON public.club_events;
CREATE POLICY club_events_insert ON public.club_events
  FOR INSERT WITH CHECK (
    created_by = (SELECT auth.uid())
    AND public.has_accepted_current_ugc_terms()
    AND NOT public.has_active_ugc_penalty(
      ARRAY['community_restriction']::public.ugc_penalty_type[]
    )
    AND (
      public.is_club_manager(club_id)
      OR EXISTS (
        SELECT 1 FROM public.club_members m
        WHERE m.club_id = club_events.club_id
          AND m.user_id = (SELECT auth.uid())
          AND m.status = 'active'
          AND m.can_create_event
      )
    )
  );

DROP POLICY IF EXISTS club_events_update ON public.club_events;
CREATE POLICY club_events_update ON public.club_events
  FOR UPDATE USING (
    public.is_admin()
    OR (
      (created_by = (SELECT auth.uid()) OR public.is_club_manager(club_id))
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  ) WITH CHECK (
    public.is_admin()
    OR (
      (created_by = (SELECT auth.uid()) OR public.is_club_manager(club_id))
      AND public.is_active_club_member(club_id)
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  );

-- 모집글도 다른 UGC 쓰기 경로와 동일하게 약관 동의·제재 게이트를 적용한다.
-- (has_* 함수가 이 파일에서 정의되므로, 원본 정책을 여기서 재정의한다. 20260714140000 파일보다 뒤.)
DROP POLICY IF EXISTS club_recruiting_posts_insert ON public.club_recruiting_posts;
CREATE POLICY club_recruiting_posts_insert ON public.club_recruiting_posts
  FOR INSERT WITH CHECK (
    public.is_admin()
    OR (
      created_by = (SELECT auth.uid())
      AND public.is_club_manager(club_id)
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  );

DROP POLICY IF EXISTS club_recruiting_posts_update ON public.club_recruiting_posts;
CREATE POLICY club_recruiting_posts_update ON public.club_recruiting_posts
  FOR UPDATE USING (
    public.is_club_manager(club_id) OR public.is_admin()
  ) WITH CHECK (
    public.is_admin()
    OR (
      public.is_club_manager(club_id)
      AND public.has_accepted_current_ugc_terms()
      AND NOT public.has_active_ugc_penalty(
        ARRAY['community_restriction']::public.ugc_penalty_type[]
      )
    )
  );

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) VALUES (
  'ugc-report-evidence',
  'ugc-report-evidence',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY ugc_report_evidence_insert ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'ugc-report-evidence'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );
CREATE POLICY ugc_report_evidence_select ON storage.objects
  FOR SELECT USING (
    bucket_id = 'ugc-report-evidence'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin()
    )
  );
CREATE POLICY ugc_report_evidence_delete ON storage.objects
  FOR DELETE USING (
    bucket_id = 'ugc-report-evidence'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin()
    )
  );

REVOKE ALL ON FUNCTION public.has_accepted_current_ugc_terms() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_current_ugc_terms() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_active_ugc_penalty(public.ugc_penalty_type[])
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_ugc_access() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_user_blocked_pair(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_commentable_club_post(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.block_user(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unblock_user(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_blocked_users() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_ugc_report(
  public.ugc_target_type,
  uuid,
  public.ugc_report_reason,
  text,
  text[]
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_resolve_ugc_report(
  uuid,
  text,
  boolean,
  public.ugc_penalty_type,
  integer,
  text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_revoke_user_penalty(uuid, text)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.has_accepted_current_ugc_terms()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.accept_current_ugc_terms()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_active_ugc_penalty(public.ugc_penalty_type[])
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_ugc_access()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_user_blocked_pair(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_commentable_club_post(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.block_user(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unblock_user(uuid)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_blocked_users()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_ugc_report(
  public.ugc_target_type,
  uuid,
  public.ugc_report_reason,
  text,
  text[]
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_resolve_ugc_report(
  uuid,
  text,
  boolean,
  public.ugc_penalty_type,
  integer,
  text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_revoke_user_penalty(uuid, text)
  TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
