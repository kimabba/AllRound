-- JY-146 P3-a: 등급 사전(grades)이 정본으로 동작하는지 검증한다.
-- CHECK 제약을 FK 로 바꿨으므로, 잘못된 등급이 거부되는 경로가 실제로 살아 있는지가 핵심.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(10);

-- 1) 사전 내용 — 종목별 등급 수와 순서.
SELECT is(
  (SELECT count(*) FROM public.grades WHERE sport = 'tennis' AND is_active),
  4::bigint,
  '테니스 등급 4개가 활성 상태다'
);
SELECT is(
  (SELECT count(*) FROM public.grades WHERE sport = 'futsal' AND is_active),
  5::bigint,
  '풋살 등급 5개가 활성 상태다'
);
SELECT is(
  (SELECT string_agg(code, ',' ORDER BY sort_order)
     FROM public.grades WHERE sport = 'futsal' AND is_active),
  'intro,beginner,intermediate,advanced,elite',
  '풋살 등급이 입문→선출 순서로 정렬된다'
);
SELECT is(
  (SELECT label_ko FROM public.grades WHERE sport = 'futsal' AND code = 'elite'),
  '선출',
  '라벨이 DB 에 있다(그동안 코드에만 있던 축)'
);

-- 2) CHECK → FK 교체가 실제로 일어났는지.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.user_sports'::regclass
       AND conname = 'user_sports_grade_check'
  ),
  '옛 CHECK 제약(user_sports_grade_check)이 제거됐다'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.user_sports'::regclass
       AND conname = 'user_sports_grade_fkey'
       AND contype = 'f'
  ),
  'user_sports 가 grades 를 복합 FK 로 참조한다'
);

-- 3) 강제력 — 사전에 없는 등급, 그리고 종목이 어긋난 등급을 거부해야 한다.
--    후자가 복합 FK 의 핵심이다. 단일 컬럼 FK 였다면 풋살 사용자에게 테니스 등급을
--    붙일 수 있다.
--    (INSERT 는 (user_id, sport) PK 충돌이 먼저 나서 FK 까지 가지 않으므로 UPDATE 로 검증한다.)
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'div5'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23503',
  NULL,
  '사전에 없는 등급(폐기된 div5)은 FK 로 거부된다'
);
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'under1y'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23503',
  NULL,
  '테니스 등급을 풋살에 붙이면 거부된다(종목 간 교차 오염 차단)'
);

-- 4) RLS — 선택지 표시는 되어야 하고, 사전 수정은 관리자만.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
SELECT is(
  (SELECT count(*) FROM public.grades),
  9::bigint,
  '로그인 사용자는 등급 사전을 읽는다'
);
SELECT throws_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('futsal', 'hacked', '침입', 99)$$,
  '42501',
  NULL,
  '일반 사용자는 등급 사전에 쓸 수 없다'
);

SELECT * FROM finish();
ROLLBACK;
