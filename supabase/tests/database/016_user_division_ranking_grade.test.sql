-- JY-135 후속: 랭킹 등급과 대회 출전 종목을 가른 뒤(20260729020000), 유저가 종목 전용
-- 부서를 자기 등급으로 갖지 못하게 하는 트리거를 검증한다.
--
-- 013 과 같은 이유로 **위반 데이터를 실제로 넣어** 본다 — 트리거는 문법만 맞으면
-- 조용히 통과하는 실수를 낳는다. 앱은 user_tennis_orgs 에 PostgREST 로 직접 쓰고
-- RLS 는 본인 행·연령만 보므로, 이 불변식을 지키는 것은 이 트리거뿐이다.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(11);

-- ── 준비 ──────────────────────────────────────────────────────────────────
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('22222222-3333-4444-8555-666666666666', 'div-guard@example.test', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, email, name, nickname, birth_date)
VALUES ('22222222-3333-4444-8555-666666666666', 'div-guard@example.test',
        '부서가드', '부서가드', '1990-01-01')
ON CONFLICT (id) DO NOTHING;

-- ── 카탈로그 전제: 분류가 실제로 갈려 있는가 ──────────────────────────────
-- 아래 통과/차단 케이스가 "우연히" 맞는 걸 막는다. 분류가 뒤집히면 여기서 먼저 깨진다.
SELECT is(
  (SELECT is_ranking_grade FROM public.tennis_divisions WHERE code = 'gj_m_beginner'),
  false, '초급자부는 대회 종목 전용이다'
);
SELECT is(
  (SELECT is_ranking_grade FROM public.tennis_divisions WHERE code = 'gj_m_masters'),
  false, '마스터즈부는 대회 종목 전용이다'
);
SELECT is(
  (SELECT is_ranking_grade FROM public.tennis_divisions WHERE code = 'gj_m_jidong'),
  false, '지동부는 대회 종목 전용이다'
);
SELECT is(
  (SELECT is_ranking_grade FROM public.tennis_divisions WHERE code = 'gj_m_gold'),
  true, '골드부는 랭킹 등급이다'
);

-- ── 통과해야 하는 것 ──────────────────────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
    VALUES ('22222222-3333-4444-8555-666666666666', 'gj', '골드부',
            ARRAY['gj_m_gold','gj_m_instructor'], true)$$,
  '랭킹 등급만 담으면 통과한다'
);

-- 미등록 코드는 통과시킨다. 의미 검증까지 하면 새 부서를 넣는 순서에 따라 저장이
-- 막힌다 — 이 트리거가 지켜야 할 불변식이 아니다(tournaments 쪽이 형식만 보는 것과 같다).
SELECT lives_ok(
  $$INSERT INTO public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
    VALUES ('22222222-3333-4444-8555-666666666666', 'kta', '미등록',
            ARRAY['kta_m_open','totally_new_code'], false)$$,
  '카탈로그에 없는 코드는 막지 않는다'
);

SELECT lives_ok(
  $$INSERT INTO public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
    VALUES ('22222222-3333-4444-8555-666666666666', 'kata', '빈배열',
            ARRAY[]::text[], false)$$,
  '빈 배열은 통과한다'
);

-- ── 막혀야 하는 것 ────────────────────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
    VALUES ('22222222-3333-4444-8555-666666666666', 'jn', '초급자부',
            ARRAY['jn_m_beginner'], false)$$,
  '23514',
  NULL,
  'INSERT 로 종목 전용 부서를 등급에 넣을 수 없다'
);

SELECT throws_ok(
  $$INSERT INTO public.user_tennis_orgs (user_id, org, division, division_codes, is_primary)
    VALUES ('22222222-3333-4444-8555-666666666666', 'gj', '지동부',
            ARRAY['gj_m_jidong'], false)$$,
  '23514',
  NULL,
  '지동부도 막힌다'
);

-- 정상 등급에 섞어 넣는 우회도 막힌다.
SELECT throws_ok(
  $$UPDATE public.user_tennis_orgs
       SET division_codes = ARRAY['gj_m_gold','gj_m_masters']
     WHERE user_id = '22222222-3333-4444-8555-666666666666' AND division = '골드부'$$,
  '23514',
  NULL,
  'UPDATE 로 종목 전용을 섞어 넣을 수 없다'
);

-- ── 데이터 정합: 시드·마이그레이션이 위반 행을 남기지 않았는가 ────────────
-- 트리거는 쓰기 시점만 본다. 이미 있는 코드를 나중에 종목 전용으로 내리는 경우는
-- user_tennis_orgs 를 건드리지 않아 발동하지 않는다(check_division_parity.py 와 이중).
SELECT is(
  (SELECT count(*) FROM public.user_tennis_orgs u
    WHERE EXISTS (
      SELECT 1 FROM unnest(u.division_codes) AS c
      JOIN public.tennis_divisions d ON d.code = c
      WHERE d.is_ranking_grade = false
    )),
  0::bigint,
  '기존 유저 행에 대회 종목 전용 부서가 남아 있지 않다'
);

SELECT * FROM finish();
ROLLBACK;
