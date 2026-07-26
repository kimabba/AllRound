-- #319 후속: 대회 등급 검증이 Edge 한 곳에만 있어 PostgREST 직행으로 우회됐다.
-- 이 테스트는 **우회가 실제로 막히는가**를 본다 — 트리거가 존재하는지가 아니라,
-- 위반 데이터를 넣었을 때 실제로 예외가 나는지로 검증한다(트리거는 문법만 맞으면
-- 조용히 통과하는 실수를 낳는다).

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(16);

-- ── 준비: 제출자 계정(트리거 검증에는 RLS 가 필요 없다 — 소유자 권한으로 직접 넣는다) ──
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('11111111-2222-4333-8444-555555555555', 'guard-test@example.test', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, email, name, nickname, birth_date)
VALUES ('11111111-2222-4333-8444-555555555555', 'guard-test@example.test', '가드테스트', '가드테스트', '1990-01-01')
ON CONFLICT (id) DO NOTHING;

-- 1) 정상 등급 코드는 통과한다.
SELECT lives_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source, submitted_by)
    VALUES ('tennis', '가드테스트 정상', current_date + 30, ARRAY['y1to3','y3to5'],
            'draft', 'user_submission', '11111111-2222-4333-8444-555555555555')$$,
  '등급 코드는 통과한다'
);

-- 2) 부서 코드도 통과한다 — grades 에 없어도 형식만 맞으면 된다(정본은 tennis_divisions).
SELECT lives_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source, submitted_by)
    VALUES ('tennis', '가드테스트 부서', current_date + 30, ARRAY['gj_m_gold','kta_m_open'],
            'draft', 'user_submission', '11111111-2222-4333-8444-555555555555')$$,
  '부서 코드는 grades 에 없어도 통과한다(크롤이 멈추지 않는다)'
);

-- 3) 빈 배열·NULL 은 통과한다 — 크롤러가 부서 미매칭 시 넣는 값이다.
SELECT lives_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('futsal', '가드테스트 빈배열', current_date + 30, ARRAY[]::text[], 'draft', 'crawler')$$,
  '빈 배열은 통과한다'
);

-- 4~7) 실제 우회 시도가 막힌다.
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 스크립트', current_date + 30,
            ARRAY['<script>alert(1)</script>'], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  'HTML/스크립트 문자열이 거부된다'
);
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 한글', current_date + 30,
            ARRAY['아무거나'], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '한글 등 형식 밖 문자가 거부된다'
);
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 대문자', current_date + 30,
            ARRAY['GJ_M_GOLD'], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '대문자가 거부된다(parseDivisionCodes 와 같은 규칙)'
);
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 길이', current_date + 30,
            ARRAY[repeat('a', 65)], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '64자를 넘는 코드가 거부된다'
);

-- 8a) NULL 원소가 막힌다 — `g !~ '...'` 는 NULL 이면 거짓이라 형식 검사만으로는 통과했다.
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 널', current_date + 30,
            ARRAY['y1to3', NULL], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  'NULL 원소가 거부된다'
);

-- 8b) 2차원 배열로 **개수 상한**을 우회할 수 없다.
-- 원소는 전부 형식이 유효해야 이 검사가 의미를 갖는다 — 하나라도 형식 위반이면
-- 형식 검사가 먼저 잡아 상한 검사가 통과한 것처럼 보인다(그렇게 만들었다가 고쳤다).
-- 30개 × 2행 = 60개: array_length(arr,1) 은 2 로 세지만 cardinality 는 60 이다.
SELECT throws_ok(
  format(
    $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
      VALUES ('tennis', '가드테스트 다차원', current_date + 30, %s, 'draft', 'user_submission')$$,
    (SELECT 'ARRAY[ARRAY[' || string_agg(quote_literal('c' || i), ',') || '],ARRAY['
                            || string_agg(quote_literal('d' || i), ',') || ']]'
       FROM generate_series(1, 30) AS i)
  ),
  '23514',
  NULL,
  '다차원 배열로 원소 개수 상한을 우회할 수 없다'
);

-- 8c) 원소가 적어도 다차원이면 거부된다 — cardinality·unnest 는 차원을 평탄화하므로
-- 개수·형식 검사만으로는 ARRAY[['y1to3','y3to5']] 가 통과했다(codex 2차).
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 중첩소형', current_date + 30,
            ARRAY[ARRAY['y1to3','y3to5']], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '원소가 적어도 2차원 배열은 거부된다'
);

-- 8d) 평면 51개도 거부된다(상한 자체의 회귀 검출).
SELECT throws_ok(
  format(
    $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
      VALUES ('tennis', '가드테스트 51개', current_date + 30, %s, 'draft', 'user_submission')$$,
    (SELECT 'ARRAY[' || string_agg(quote_literal('e' || i), ',') || ']'
       FROM generate_series(1, 51) AS i)
  ),
  '23514',
  NULL,
  '평면 배열 51개가 거부된다'
);

-- 8e) 빈 문자열 원소.
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 빈문자', current_date + 30,
            ARRAY['y1to3',''], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '빈 문자열 원소가 거부된다'
);

-- 8f) 후행 공백 — trim 해서 통과시키지 않는다(코드는 정확일치가 정본이다).
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 후행공백', current_date + 30,
            ARRAY['y1to3 '], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '후행 공백이 붙은 코드가 거부된다'
);

-- 8g) 동형문자(키릴 'а' U+0430)는 ASCII 'a' 가 아니다. collate "C" 로 범위를 고정했다.
SELECT throws_ok(
  $$INSERT INTO public.tournaments (sport, title, start_date, eligible_grades, status, source)
    VALUES ('tennis', '가드테스트 동형문자', current_date + 30,
            ARRAY['kt' || U&'\0430' || '_m_open'], 'draft', 'user_submission')$$,
  '23514',
  NULL,
  '키릴 동형문자가 섞인 코드가 거부된다'
);

-- 9) UPDATE 경로도 막힌다 — INSERT 만 막으면 tournaments_self_draft_update 로 우회된다.
SELECT throws_ok(
  $$UPDATE public.tournaments SET eligible_grades = ARRAY['bad value']
     WHERE title = '가드테스트 정상'$$,
  '23514',
  NULL,
  'UPDATE 로 바꿔치기하는 경로도 막힌다'
);

-- 9) anon 은 save_user_sports 를 실행할 수 없다(최소권한).
SELECT ok(
  NOT has_function_privilege('anon', 'public.save_user_sports(jsonb)', 'EXECUTE'),
  'anon 에게 save_user_sports EXECUTE 가 없다'
);

SELECT * FROM finish();
ROLLBACK;
