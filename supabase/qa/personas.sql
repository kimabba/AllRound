-- AllRound Night Shift 로컬 전용 합성 fixture.
-- scripts/qa/assert_local_supabase.sh를 통과한 뒤 `supabase db query --local`로만 실행한다.
-- 실제 사용자·이메일·전화번호·사진·대화는 포함하지 않는다.

BEGIN;

DO $$
DECLARE
  qa_password text := 'QaLocal-Only-2026!';
BEGIN
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token,
    email_change, email_change_token_new, email_change_token_current
  )
  SELECT
    '00000000-0000-0000-0000-000000000000'::uuid,
    persona.id,
    'authenticated',
    'authenticated',
    persona.email,
    crypt(qa_password, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', persona.display_name),
    false,
    '', '', '', '', ''
  FROM (VALUES
    ('00000000-0000-4000-8000-000000000001'::uuid, 'qa-admin@allround.invalid',     'QA 관리자'),
    ('00000000-0000-4000-8000-000000000002'::uuid, 'qa-owner@allround.invalid',     'QA 오너'),
    ('00000000-0000-4000-8000-000000000003'::uuid, 'qa-manager@allround.invalid',   'QA 매니저'),
    ('00000000-0000-4000-8000-000000000004'::uuid, 'qa-delegate@allround.invalid',  'QA 위임회원'),
    ('00000000-0000-4000-8000-000000000005'::uuid, 'qa-member@allround.invalid',    'QA 일반회원'),
    ('00000000-0000-4000-8000-000000000006'::uuid, 'qa-applicant@allround.invalid', 'QA 가입신청자'),
    ('00000000-0000-4000-8000-000000000007'::uuid, 'qa-offender@allround.invalid',  'QA 제재대상'),
    ('00000000-0000-4000-8000-000000000008'::uuid, 'qa-empty@allround.invalid',     'QA 미완성계정')
  ) AS persona(id, email, display_name)
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data,
    raw_user_meta_data = EXCLUDED.raw_user_meta_data,
    updated_at = now();
END;
$$;

UPDATE public.users
SET
  name = profile.name,
  nickname = profile.nickname,
  birth_date = DATE '1990-01-01',
  primary_region = profile.region,
  interest_regions = ARRAY[profile.region],
  ugc_terms_version = '2026-07-15',
  ugc_terms_accepted_at = now()
FROM (VALUES
  ('00000000-0000-4000-8000-000000000001'::uuid, 'QA 관리자',    'qa_admin',     'seoul'),
  ('00000000-0000-4000-8000-000000000002'::uuid, 'QA 오너',      'qa_owner',     'gwangju'),
  ('00000000-0000-4000-8000-000000000003'::uuid, 'QA 매니저',    'qa_manager',   'gwangju'),
  ('00000000-0000-4000-8000-000000000004'::uuid, 'QA 위임회원',  'qa_delegate',  'jeonnam'),
  ('00000000-0000-4000-8000-000000000005'::uuid, 'QA 일반회원',  'qa_member',    'seoul'),
  ('00000000-0000-4000-8000-000000000006'::uuid, 'QA 가입신청자','qa_applicant', 'jeju'),
  ('00000000-0000-4000-8000-000000000007'::uuid, 'QA 제재대상',  'qa_offender',  'busan')
) AS profile(id, name, nickname, region)
WHERE public.users.id = profile.id;

-- QA-EMPTY는 auth/public.users만 유지하고 프로필·종목을 채우지 않는다.
UPDATE public.users
SET birth_date = NULL,
    nickname = NULL,
    primary_region = NULL,
    interest_regions = '{}',
    ugc_terms_version = NULL,
    ugc_terms_accepted_at = NULL
WHERE id = '00000000-0000-4000-8000-000000000008'::uuid;

-- role 변경 방지 트리거를 영구 비활성화하지 않고 현재 트랜잭션의 한 문장만 우회한다.
SET LOCAL session_replication_role = replica;
UPDATE public.users
SET role = CASE
  WHEN id = '00000000-0000-4000-8000-000000000001'::uuid THEN 'admin'::public.user_role
  ELSE 'user'::public.user_role
END
WHERE id BETWEEN
  '00000000-0000-4000-8000-000000000001'::uuid AND
  '00000000-0000-4000-8000-000000000008'::uuid;
SET LOCAL session_replication_role = origin;

DELETE FROM public.user_sports
WHERE user_id BETWEEN
  '00000000-0000-4000-8000-000000000001'::uuid AND
  '00000000-0000-4000-8000-000000000008'::uuid;

INSERT INTO public.user_sports (user_id, sport, grade, is_primary) VALUES
  ('00000000-0000-4000-8000-000000000001', 'tennis', 'over5y',      true),
  ('00000000-0000-4000-8000-000000000001', 'futsal', 'advanced',    false),
  ('00000000-0000-4000-8000-000000000002', 'tennis', 'y3to5',       true),
  ('00000000-0000-4000-8000-000000000003', 'tennis', 'y1to3',       true),
  ('00000000-0000-4000-8000-000000000003', 'futsal', 'intermediate', false),
  ('00000000-0000-4000-8000-000000000004', 'tennis', 'under1y',     true),
  ('00000000-0000-4000-8000-000000000005', 'tennis', 'y1to3',       true),
  ('00000000-0000-4000-8000-000000000005', 'futsal', 'beginner',    false),
  ('00000000-0000-4000-8000-000000000006', 'futsal', 'intro',       true),
  ('00000000-0000-4000-8000-000000000007', 'futsal', 'elite',       true);

DELETE FROM public.user_tennis_orgs
WHERE user_id BETWEEN
  '00000000-0000-4000-8000-000000000001'::uuid AND
  '00000000-0000-4000-8000-000000000008'::uuid;

INSERT INTO public.user_tennis_orgs
  (user_id, org, division, division_codes, is_primary, region_code)
VALUES
  ('00000000-0000-4000-8000-000000000001', 'kta',  '남자오픈',   ARRAY['kta_m_open'],    true, 'seoul'),
  ('00000000-0000-4000-8000-000000000002', 'gj',   '남자일반부', ARRAY['gj_m_general'],  true, 'gwangju'),
  ('00000000-0000-4000-8000-000000000003', 'gj',   '남자신인부', ARRAY['gj_m_rookie'],   true, 'gwangju'),
  ('00000000-0000-4000-8000-000000000004', 'jn',   '초급자부',   ARRAY['jn_m_beginner'], true, 'jeonnam'),
  ('00000000-0000-4000-8000-000000000005', 'kata', '4부',        ARRAY['kata_4'],         true, 'seoul')
ON CONFLICT (user_id, org, division) DO UPDATE SET
  division_codes = EXCLUDED.division_codes,
  is_primary = EXCLUDED.is_primary,
  region_code = EXCLUDED.region_code;

INSERT INTO public.tournaments
  (id, sport, title, start_date, application_deadline, region, region_code,
   eligible_grades, source, status, submitted_by, approved_by, approved_at)
VALUES
  ('00000000-0000-4000-8000-000000000101', 'tennis', 'QA 광주 일반부 공개대회',
   current_date + 14, current_date + 7, '광주', 'gwangju', ARRAY['gj_m_general'],
   'qa-night-shift', 'published', '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000001', now()),
  ('00000000-0000-4000-8000-000000000102', 'tennis', 'QA 오너 검수대기 제보',
   current_date + 21, current_date + 14, '광주', 'gwangju', ARRAY['gj_m_general'],
   'qa-night-shift', 'draft', '00000000-0000-4000-8000-000000000002', NULL, NULL),
  ('00000000-0000-4000-8000-000000000103', 'futsal', 'QA 풋살 입문 공개대회',
   current_date + 10, current_date + 5, '제주', 'jeju', ARRAY['intro', 'beginner'],
   'qa-night-shift', 'published', '00000000-0000-4000-8000-000000000006',
   '00000000-0000-4000-8000-000000000001', now()),
  ('00000000-0000-4000-8000-000000000104', 'futsal', 'QA 거절된 비공개대회',
   current_date + 30, current_date + 20, '부산', 'busan', ARRAY['elite'],
   'qa-night-shift', 'rejected', '00000000-0000-4000-8000-000000000007',
   NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  start_date = EXCLUDED.start_date,
  application_deadline = EXCLUDED.application_deadline,
  eligible_grades = EXCLUDED.eligible_grades,
  status = EXCLUDED.status,
  submitted_by = EXCLUDED.submitted_by,
  approved_by = EXCLUDED.approved_by,
  approved_at = EXCLUDED.approved_at;

INSERT INTO public.tournament_favorites (user_id, tournament_id) VALUES
  ('00000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000101'),
  ('00000000-0000-4000-8000-000000000006', '00000000-0000-4000-8000-000000000103')
ON CONFLICT DO NOTHING;

INSERT INTO public.clubs
  (id, sport, name, region, address, description, created_by, status, approved_by, approved_at)
VALUES
  ('00000000-0000-4000-8000-000000000201', 'tennis', 'QA 광주 테니스 클럽',
   '광주', '합성 테스트 주소', '실제 회원과 무관한 QA 전용 클럽',
   '00000000-0000-4000-8000-000000000002', 'approved',
   '00000000-0000-4000-8000-000000000001', now())
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  status = EXCLUDED.status,
  created_by = EXCLUDED.created_by,
  approved_by = EXCLUDED.approved_by,
  approved_at = EXCLUDED.approved_at;

INSERT INTO public.club_members
  (club_id, user_id, role, status, can_kick, can_create_event, can_post_notice)
VALUES
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000002', 'owner',   'active', true,  true,  true),
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000003', 'manager', 'active', false, true,  true),
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000004', 'member',  'active', false, true,  true),
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000005', 'member',  'active', false, false, false),
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000007', 'member',  'active', false, false, false)
ON CONFLICT (club_id, user_id) DO UPDATE SET
  role = EXCLUDED.role,
  status = EXCLUDED.status,
  can_kick = EXCLUDED.can_kick,
  can_create_event = EXCLUDED.can_create_event,
  can_post_notice = EXCLUDED.can_post_notice;

INSERT INTO public.club_join_requests
  (id, club_id, user_id, message, status)
VALUES
  ('00000000-0000-4000-8000-000000000301',
   '00000000-0000-4000-8000-000000000201',
   '00000000-0000-4000-8000-000000000006',
   'QA 합성 가입 신청', 'pending')
ON CONFLICT (id) DO UPDATE SET
  message = EXCLUDED.message,
  status = EXCLUDED.status,
  reviewed_by = NULL,
  reviewed_at = NULL;

INSERT INTO public.notifications
  (id, user_id, type, title, body, status)
VALUES
  ('00000000-0000-4000-8000-000000000401', '00000000-0000-4000-8000-000000000005',
   'club_notice', 'QA 회원 알림', '합성 알림 본문', 'sent'),
  ('00000000-0000-4000-8000-000000000402', '00000000-0000-4000-8000-000000000006',
   'club_event', 'QA 신청자 알림', '다른 계정에서 보이면 안 되는 합성 본문', 'sent')
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  title = EXCLUDED.title,
  body = EXCLUDED.body,
  is_read = false,
  status = EXCLUDED.status;

INSERT INTO public.chat_messages
  (id, user_id, conversation_id, role, content)
VALUES
  ('00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000005',
   '00000000-0000-4000-8000-000000000551', 'user', 'QA 회원의 합성 대화'),
  ('00000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-000000000006',
   '00000000-0000-4000-8000-000000000552', 'user', 'QA 신청자의 비공개 합성 대화')
ON CONFLICT (id) DO UPDATE SET content = EXCLUDED.content;

INSERT INTO public.user_blocks (blocker_id, blocked_id)
VALUES ('00000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000007')
ON CONFLICT DO NOTHING;

INSERT INTO public.ugc_reports
  (id, reporter_id, reported_user_id, target_type, target_id, reason,
   details, content_snapshot, status)
VALUES
  ('00000000-0000-4000-8000-000000000601',
   '00000000-0000-4000-8000-000000000005',
   '00000000-0000-4000-8000-000000000007',
   'user', '00000000-0000-4000-8000-000000000007', 'privacy',
   'QA 합성 신고', '{"source":"qa-night-shift","contains_real_pii":false}', 'pending')
ON CONFLICT (id) DO UPDATE SET
  details = EXCLUDED.details,
  content_snapshot = EXCLUDED.content_snapshot,
  status = EXCLUDED.status;

INSERT INTO public.user_penalties
  (id, user_id, penalty_type, report_id, reason, starts_at, ends_at, created_by)
VALUES
  ('00000000-0000-4000-8000-000000000701',
   '00000000-0000-4000-8000-000000000007',
   'community_restriction',
   '00000000-0000-4000-8000-000000000601',
   'QA 합성 제재', now() - interval '1 hour', now() + interval '7 days',
   '00000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO UPDATE SET
  reason = EXCLUDED.reason,
  starts_at = EXCLUDED.starts_at,
  ends_at = EXCLUDED.ends_at,
  revoked_at = NULL,
  revoked_by = NULL,
  revoke_reason = NULL;

COMMIT;
