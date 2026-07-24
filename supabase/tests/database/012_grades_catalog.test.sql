-- JY-146 P3-a: 등급 사전(grades)이 정본으로 동작하는지 검증한다.
-- CHECK 제약을 FK 로 바꿨으므로, 잘못된 등급이 거부되는 경로가 실제로 살아 있는지가 핵심.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(15);

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
--    붙일 수 있다. BEFORE 트리거(활성 등급 강제)가 FK 보다 먼저 걸리므로 기대 코드는
--    23514 다 — FK 는 그 뒤의 방어선이고, 존재 자체는 위 pg_constraint 검사가 지킨다.
--    (INSERT 는 (user_id, sport) PK 충돌이 먼저 나서 제약까지 가지 않으므로 UPDATE 로 검증한다.)
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'div5'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '사전에 없는 등급(폐기된 div5)은 거부된다'
);
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'under1y'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '테니스 등급을 풋살에 붙이면 거부된다(종목 간 교차 오염 차단)'
);

-- 4) 폐기 등급 — FK 는 "존재"만 보므로 트리거가 신규 배정을 막아야 한다.
--    기존 행은 남겨야 하므로(과거 데이터 보존) FK 로는 표현할 수 없는 규칙이다.
UPDATE public.grades SET is_active = false WHERE sport = 'futsal' AND code = 'elite';
SELECT throws_ok(
  $$UPDATE public.user_sports SET grade = 'elite'
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '23514',
  NULL,
  '폐기된(is_active=false) 등급은 새로 배정할 수 없다'
);
SELECT lives_ok(
  $$UPDATE public.grades SET is_active = false WHERE sport = 'futsal' AND code = 'beginner'$$,
  '이미 그 등급을 쓰는 사용자가 있어도 폐기 처리는 가능하다(기존 행 보존)'
);
-- 폐기된 등급을 이미 가진 사용자가 프로필의 다른 값을 저장해도 막히면 안 된다.
-- (트리거 WHEN 절이 없으면 값이 그대로여도 발동해 저장 자체가 실패한다.)
SELECT lives_ok(
  $$UPDATE public.user_sports SET grade = grade, is_primary = is_primary
     WHERE user_id = '00000000-0000-4000-8000-000000000005' AND sport = 'futsal'$$,
  '폐기 등급을 가진 기존 행은 값이 그대로면 재저장할 수 있다'
);
UPDATE public.grades SET is_active = true WHERE sport = 'futsal';

-- 5) RLS — 선택지 표시는 되어야 하고, 사전 수정은 관리자만.
--    관리자 경로가 통째로 막혀도 통과하지 않도록 성공 경로까지 확인한다.
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

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
SELECT lives_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('futsal', 'qa_probe', 'QA', 99)$$,
  '관리자는 등급을 추가할 수 있다(운영 경로 — 등급 관리가 INSERT 로 끝난다)'
);
-- 관리자 INSERT 가 운영 경로인 이상, 종목 간 code 중복은 DB 가 막아야 한다.
-- 클라이언트 라벨 맵이 code 단일 키라 겹치면 한쪽이 다른 종목 라벨을 덮어쓴다.
SELECT throws_ok(
  $$INSERT INTO public.grades (sport, code, label_ko, sort_order)
    VALUES ('tennis', 'advanced', '상급', 9)$$,
  '23505',
  NULL,
  '다른 종목이 이미 쓰는 code 는 추가할 수 없다'
);

SELECT * FROM finish();
ROLLBACK;
