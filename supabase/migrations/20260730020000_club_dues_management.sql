-- 클럽 월별 회비 장부: 운영진 기록, 회원 본인 조회, 미납 알림, 변경 이력.

BEGIN;

CREATE TABLE public.club_dues_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  period_month date NOT NULL,
  amount integer NOT NULL,
  due_date date,
  account_info text,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_dues_period_month_first_day
    CHECK (period_month = date_trunc('month', period_month)::date),
  CONSTRAINT club_dues_period_amount_range
    CHECK (amount BETWEEN 0 AND 1000000),
  CONSTRAINT club_dues_period_account_length
    CHECK (account_info IS NULL OR char_length(account_info) <= 300),
  UNIQUE (club_id, period_month)
);

CREATE TABLE public.club_dues_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id uuid NOT NULL REFERENCES public.club_dues_periods(id) ON DELETE CASCADE,
  -- 탈퇴해도 장부의 줄은 남긴다. 사람 연결고리만 끊고 표시용 이름 스냅샷을 남기는
  -- 방식은 게시글 익명화(club_posts.author_id ON DELETE SET NULL)와 같다.
  -- 회비는 "냈다/안 냈다" 분쟁 데이터라 삭제 시점이 곧 증거 소멸 시점이다.
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  member_name text,
  status text NOT NULL DEFAULT 'unpaid'
    CHECK (status IN ('paid', 'unpaid', 'exempt')),
  amount_paid integer,
  note text,
  paid_at timestamptz,
  updated_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_dues_payment_amount_range
    CHECK (amount_paid IS NULL OR amount_paid BETWEEN 0 AND 1000000),
  CONSTRAINT club_dues_payment_note_length
    CHECK (note IS NULL OR char_length(note) <= 300),
  UNIQUE (period_id, user_id)
);

CREATE TABLE public.club_dues_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id uuid NOT NULL REFERENCES public.club_dues_payments(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  previous_status text,
  next_status text NOT NULL,
  -- 상태만 남기면 "얼마를 언제 냈던 건지"가 사라진다. 되돌릴 때 amount_paid·paid_at
  -- 이 NULL 로 소거되므로 이전 값을 여기 남겨야 복원 근거가 생긴다.
  previous_amount_paid integer,
  previous_paid_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_dues_audit_previous_status
    CHECK (previous_status IS NULL OR previous_status IN ('paid', 'unpaid', 'exempt')),
  CONSTRAINT club_dues_audit_next_status
    CHECK (next_status IN ('paid', 'unpaid', 'exempt')),
  CONSTRAINT club_dues_audit_note_length
    CHECK (note IS NULL OR char_length(note) <= 300)
);

CREATE INDEX club_dues_periods_club_month_idx
  ON public.club_dues_periods (club_id, period_month DESC);
CREATE INDEX club_dues_payments_period_status_idx
  ON public.club_dues_payments (period_id, status);
CREATE INDEX club_dues_payments_user_idx
  ON public.club_dues_payments (user_id, updated_at DESC);
CREATE INDEX club_dues_audit_payment_created_idx
  ON public.club_dues_audit (payment_id, created_at DESC);

ALTER TABLE public.club_dues_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_dues_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_dues_audit ENABLE ROW LEVEL SECURITY;

CREATE POLICY club_dues_periods_member_select ON public.club_dues_periods
  FOR SELECT USING (
    public.is_active_club_member(club_id) OR public.is_admin()
  );

CREATE POLICY club_dues_payments_member_select ON public.club_dues_payments
  FOR SELECT USING (
    user_id = (SELECT auth.uid())
    OR public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.club_dues_periods period
      WHERE period.id = club_dues_payments.period_id
        AND public.is_club_manager(period.club_id)
    )
  );

CREATE POLICY club_dues_audit_manager_select ON public.club_dues_audit
  FOR SELECT USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.club_dues_payments payment
      JOIN public.club_dues_periods period ON period.id = payment.period_id
      WHERE payment.id = club_dues_audit.payment_id
        AND public.is_club_manager(period.club_id)
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.club_dues_periods
  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.club_dues_payments
  FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.club_dues_audit
  FROM anon, authenticated;
GRANT SELECT ON public.club_dues_periods, public.club_dues_payments
  TO authenticated;
GRANT SELECT ON public.club_dues_audit TO authenticated;
GRANT ALL ON public.club_dues_periods, public.club_dues_payments,
  public.club_dues_audit TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.club_dues_audit_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.upsert_club_dues_period(
  p_club_id uuid,
  p_period_month date,
  p_amount integer,
  p_due_date date DEFAULT NULL,
  p_account_info text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_period_id uuid;
  v_month date := date_trunc('month', p_period_month)::date;
BEGIN
  IF v_actor IS NULL OR NOT public.is_club_manager(p_club_id) THEN
    RAISE EXCEPTION 'club_manager_required' USING ERRCODE = '42501';
  END IF;
  IF p_amount < 0 OR p_amount > 1000000 THEN
    RAISE EXCEPTION 'invalid_amount' USING ERRCODE = '22023';
  END IF;
  IF p_account_info IS NOT NULL AND char_length(trim(p_account_info)) > 300 THEN
    RAISE EXCEPTION 'account_info_too_long' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.club_dues_periods (
    club_id, period_month, amount, due_date, account_info, created_by
  )
  VALUES (
    p_club_id,
    v_month,
    p_amount,
    p_due_date,
    NULLIF(trim(p_account_info), ''),
    v_actor
  )
  ON CONFLICT (club_id, period_month) DO UPDATE
  SET amount = EXCLUDED.amount,
      due_date = EXCLUDED.due_date,
      account_info = EXCLUDED.account_info,
      updated_at = now()
  RETURNING id INTO v_period_id;

  INSERT INTO public.club_dues_payments (period_id, user_id)
  SELECT v_period_id, member.user_id
  FROM public.club_members member
  WHERE member.club_id = p_club_id
    AND member.status = 'active'
  ON CONFLICT (period_id, user_id) DO NOTHING;

  RETURN v_period_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_club_due_status(
  p_period_id uuid,
  p_user_ids uuid[],
  p_status text,
  p_note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_club_id uuid;
  v_count integer := 0;
  v_payment record;
BEGIN
  SELECT club_id INTO v_club_id
  FROM public.club_dues_periods
  WHERE id = p_period_id;

  IF v_actor IS NULL OR v_club_id IS NULL
     OR NOT public.is_club_manager(v_club_id) THEN
    RAISE EXCEPTION 'club_manager_required' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('paid', 'unpaid', 'exempt') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;
  IF coalesce(array_length(p_user_ids, 1), 0) = 0
     OR array_length(p_user_ids, 1) > 200 THEN
    RAISE EXCEPTION 'invalid_user_count' USING ERRCODE = '22023';
  END IF;
  IF p_note IS NOT NULL AND char_length(trim(p_note)) > 300 THEN
    RAISE EXCEPTION 'note_too_long' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.club_dues_payments (period_id, user_id, member_name)
  SELECT p_period_id, member.user_id, u.name
  FROM public.club_members member
  JOIN public.users u ON u.id = member.user_id
  WHERE member.club_id = v_club_id
    AND member.status = 'active'
    AND member.user_id = ANY(p_user_ids)
  ON CONFLICT (period_id, user_id) DO NOTHING;

  FOR v_payment IN
    SELECT id, status, amount_paid, paid_at
    FROM public.club_dues_payments
    WHERE period_id = p_period_id
      AND user_id = ANY(p_user_ids)
    -- 잠금 순서를 고정한다. 운영진 둘이 겹치는 멤버를 역순으로 잠그면 교착이 난다.
    ORDER BY id
    FOR UPDATE
  LOOP
    UPDATE public.club_dues_payments
    SET status = p_status,
        amount_paid = CASE
          WHEN p_status = 'paid' THEN (
            SELECT amount FROM public.club_dues_periods WHERE id = p_period_id
          )
          ELSE NULL
        END,
        -- 이미 paid 인 멤버를 다시 paid 로 일괄 지정해도 원래 납부 시각을 지킨다.
        paid_at = CASE
          WHEN p_status = 'paid' THEN COALESCE(v_payment.paid_at, now())
          ELSE NULL
        END,
        note = NULLIF(trim(p_note), ''),
        updated_by = v_actor,
        updated_at = now()
    WHERE id = v_payment.id;

    INSERT INTO public.club_dues_audit (
      payment_id, actor_id, previous_status, next_status,
      previous_amount_paid, previous_paid_at, note
    )
    VALUES (
      v_payment.id, v_actor, v_payment.status, p_status,
      v_payment.amount_paid, v_payment.paid_at, NULLIF(trim(p_note), '')
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'tournament_d3', 'tournament_deadline',
    'club_notice', 'club_event', 'club_mention',
    'club_comment', 'club_event_reminder', 'club_attendance_change',
    'club_join_request', 'club_join_approved', 'club_join_rejected',
    'club_approval_request', 'club_inquiry_received', 'club_inquiry_reply',
    'club_dues_reminder'
  ));

CREATE OR REPLACE FUNCTION public.send_club_dues_reminders(
  p_period_id uuid,
  p_user_ids uuid[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_period public.club_dues_periods%ROWTYPE;
  v_count integer := 0;
BEGIN
  SELECT * INTO v_period
  FROM public.club_dues_periods
  WHERE id = p_period_id;

  IF v_actor IS NULL OR v_period.id IS NULL
     OR NOT public.is_club_manager(v_period.club_id) THEN
    RAISE EXCEPTION 'club_manager_required' USING ERRCODE = '42501';
  END IF;
  IF coalesce(array_length(p_user_ids, 1), 0) = 0
     OR array_length(p_user_ids, 1) > 200 THEN
    RAISE EXCEPTION 'invalid_user_count' USING ERRCODE = '22023';
  END IF;

  -- 장부에 행이 아직 없는 멤버(뒤늦게 가입)는 화면에선 미납으로 보이는데 알림만
  -- 조용히 빠졌다. set_club_due_status 와 같은 방식으로 행을 먼저 만든다.
  INSERT INTO public.club_dues_payments (period_id, user_id, member_name)
  SELECT p_period_id, member.user_id, u.name
  FROM public.club_members member
  JOIN public.users u ON u.id = member.user_id
  WHERE member.club_id = v_period.club_id
    AND member.status = 'active'
    AND member.user_id = ANY(p_user_ids)
  ON CONFLICT (period_id, user_id) DO NOTHING;

  INSERT INTO public.notifications (
    user_id, type, title, body, reference_type, reference_id, club_id, status
  )
  SELECT
    payment.user_id,
    'club_dues_reminder',
    '회비 납부 안내',
    format(
      '%s월 회비 %s원이 아직 미납 상태입니다.',
      extract(month FROM v_period.period_month)::integer,
      to_char(v_period.amount, 'FM999,999,999')
    ),
    'club_dues',
    payment.id,
    v_period.club_id,
    'sent'
  FROM public.club_dues_payments payment
  WHERE payment.period_id = p_period_id
    AND payment.status = 'unpaid'
    AND payment.user_id = ANY(p_user_ids)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_club_dues_period(
  uuid, date, integer, date, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_club_due_status(
  uuid, uuid[], text, text
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.send_club_dues_reminders(
  uuid, uuid[]
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_club_dues_period(
  uuid, date, integer, date, text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_club_due_status(
  uuid, uuid[], text, text
) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.send_club_dues_reminders(
  uuid, uuid[]
) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
