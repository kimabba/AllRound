-- JY-135: 협회 표시 정본(label_ko·short_label·sort_order)이 DB 에 있는지 검증한다.
-- 앱이 이 값을 그대로 화면에 쓰므로, 값이 어긋나면 사용자 화면 문구가 바뀐다.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO public, extensions;

SELECT plan(6);

SELECT has_column('public', 'tennis_orgs', 'label_ko', 'tennis_orgs 에 label_ko 가 있다');
SELECT has_column('public', 'tennis_orgs', 'sort_order', 'tennis_orgs 에 sort_order 가 있다');

-- sort_order 는 값을 안 정해도 INSERT 되어야 한다(백과장이 숫자를 산정할 필요 없음).
SELECT col_not_null('public', 'tennis_orgs', 'sort_order', 'sort_order 는 NOT NULL 이다');
SELECT col_default_is('public', 'tennis_orgs', 'sort_order', '1000',
  'sort_order 기본값은 1000 이라 미지정 행이 끝으로 모인다');

-- 표시 문자열이 현재 앱과 동일해야 한다. 다르면 화면 문구가 바뀐다.
SELECT is(
  (SELECT label_ko FROM public.tennis_orgs WHERE code = 'kta'),
  '대한테니스협회 (KTA)',
  'label_ko 는 앱이 쓰던 완성형 문자열이다'
);
SELECT is(
  (SELECT string_agg(short_label, ',' ORDER BY code)
     FROM public.tennis_orgs WHERE code IN ('gj', 'jn', 'local')),
  '광주협회,전남협회,시·군/클럽',
  '짧은 라벨이 앱 문자열로 백필됐다(GJTA/JNTA/null 아님)'
);

SELECT * FROM finish();
ROLLBACK;
