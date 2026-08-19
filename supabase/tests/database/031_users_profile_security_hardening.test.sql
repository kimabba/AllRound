BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(9);

-- ═══ 1) name/nickname 길이 CHECK ═══
SELECT throws_ok(
  $$UPDATE public.users SET name = repeat('가', 31)
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  '23514',
  NULL,
  '이름 31자는 CHECK로 막힌다'
);
SELECT lives_ok(
  $$UPDATE public.users SET name = repeat('가', 30)
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  '이름 30자는 통과한다'
);
SELECT throws_ok(
  $$UPDATE public.users SET nickname = ''
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  '23514',
  NULL,
  '빈 닉네임은 CHECK로 막힌다'
);

-- ═══ 2) avatar_url 도메인 화이트리스트 ═══
SELECT throws_ok(
  $$UPDATE public.users SET avatar_url = 'https://evil.example.com/x.png'
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  '23514',
  NULL,
  '외부 URL 아바타는 CHECK로 막힌다'
);
SELECT lives_ok(
  $$UPDATE public.users SET avatar_url =
    'https://bsjdgwmveokanclqwtvx.supabase.co/storage/v1/object/public/profile-avatars/'
    || '00000000-0000-4000-8000-000000000005/avatar.jpg?v=123'
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  '우리 저장소의 avatar.jpg 경로(캐시버스터 포함)는 통과한다'
);

-- ═══ 3) 약관 동의 컬럼 직접 쓰기 차단 ═══
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);

SELECT throws_ok(
  $$UPDATE public.users SET ugc_terms_version = '9999-99-99', ugc_terms_accepted_at = now()
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  'P0001',
  'ugc_terms 컬럼은 accept_current_ugc_terms() RPC로만 변경할 수 있습니다',
  '약관 화면을 거치지 않은 직접 UPDATE는 막힌다'
);

SELECT lives_ok(
  $$SELECT public.accept_current_ugc_terms()$$,
  'RPC 경로로는 약관 동의 컬럼을 쓸 수 있다'
);

-- ═══ 4) 닉네임 금칙어 필터 ═══
SELECT throws_ok(
  $$UPDATE public.users SET nickname = '시발놈'
    WHERE id = '00000000-0000-4000-8000-000000000005'::uuid$$,
  'P0001',
  'UGC_CONTENT_BLOCKED',
  '금칙어가 들어간 닉네임은 막힌다'
);

RESET ROLE;

-- ═══ 5) B1 회귀: users 분기 추가가 club_posts UGC 필터를 깨지 않는다 ═══
-- (enforce_ugc_text_policy가 NEW.nickname을 직접 참조했다면 nickname 컬럼이
--  없는 club_posts 쓰기가 'record "new" has no field "nickname"'으로 실패했을 것)
INSERT INTO public.clubs (id, sport, name)
VALUES ('00000000-0000-4000-8000-0000000000c1'::uuid, 'tennis', 'QA 테스트 클럽');

SELECT lives_ok(
  $$INSERT INTO public.club_posts (club_id, author_id, tag, title, body)
    VALUES (
      '00000000-0000-4000-8000-0000000000c1'::uuid,
      '00000000-0000-4000-8000-000000000005'::uuid,
      'free', '정상 제목', '정상 본문입니다'
    )$$,
  'users 분기 추가 후에도 club_posts 글쓰기는 정상 동작한다'
);

SELECT * FROM finish();
ROLLBACK;
