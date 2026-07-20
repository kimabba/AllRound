-- 가입 전 회원과 클럽 운영진의 비공개 문의 대화.

BEGIN;

CREATE TABLE public.club_inquiry_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, requester_id)
);

CREATE TABLE public.club_inquiry_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.club_inquiry_threads(id) ON DELETE CASCADE,
  sender_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX club_inquiry_threads_club_recent_idx
  ON public.club_inquiry_threads (club_id, last_message_at DESC);
CREATE INDEX club_inquiry_threads_requester_recent_idx
  ON public.club_inquiry_threads (requester_id, last_message_at DESC);
CREATE INDEX club_inquiry_messages_thread_created_idx
  ON public.club_inquiry_messages (thread_id, created_at);

ALTER TABLE public.club_inquiry_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_inquiry_messages ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.can_access_club_inquiry(p_thread_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.club_inquiry_threads thread
    WHERE thread.id = p_thread_id
      AND (
        thread.requester_id = (SELECT auth.uid())
        OR public.is_admin()
        OR EXISTS (
          SELECT 1
          FROM public.club_members member
          WHERE member.club_id = thread.club_id
            AND member.user_id = (SELECT auth.uid())
            AND member.status = 'active'
            AND member.role IN ('owner', 'manager')
        )
      )
  );
$$;

CREATE POLICY club_inquiry_threads_participant_select
  ON public.club_inquiry_threads
  FOR SELECT USING (public.can_access_club_inquiry(id));

CREATE POLICY club_inquiry_messages_participant_select
  ON public.club_inquiry_messages
  FOR SELECT USING (public.can_access_club_inquiry(thread_id));

-- 쓰기는 약관·제재·차단·알림을 한 경로에서 처리하는 Edge Function만 수행한다.
REVOKE INSERT, UPDATE, DELETE ON public.club_inquiry_threads
  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.club_inquiry_messages
  FROM anon, authenticated;
GRANT SELECT ON public.club_inquiry_threads, public.club_inquiry_messages
  TO authenticated;

REVOKE ALL ON FUNCTION public.can_access_club_inquiry(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_club_inquiry(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enforce_club_inquiry_text_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_text text := NEW.body;
  v_normalized text;
  v_term text;
BEGIN
  v_normalized := regexp_replace(lower(v_text), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g');

  SELECT regexp_replace(lower(term.term), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g')
  INTO v_term
  FROM public.ugc_moderation_terms term
  WHERE term.active
    AND v_normalized LIKE '%' || regexp_replace(
      lower(term.term), '[^a-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]+', '', 'g'
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

CREATE TRIGGER club_inquiry_messages_ugc_filter
  BEFORE INSERT OR UPDATE OF body ON public.club_inquiry_messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_club_inquiry_text_policy();

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request',
    'club_inquiry_received', 'club_inquiry_reply'
  ));

COMMIT;
