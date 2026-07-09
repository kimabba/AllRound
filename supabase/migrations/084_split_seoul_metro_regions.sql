-- 084: Split Seoul metro onboarding taxonomy into Seoul/Gyeonggi/Incheon.
-- Keep seoul_metro as a legacy compatibility code for existing coarse data.

INSERT INTO public.regions (code, display_name_ko, governing_associations, uses_kato, uses_kata, notes) VALUES
  ('seoul',          '서울',  '{"kta","kato","kata"}', true, true, '서울. 전국 단위 협회 다수.'),
  ('gyeonggi',       '경기',  '{"kta","kato","kata"}', true, true, '경기도. 전국 단위 협회 다수.'),
  ('incheon',        '인천',  '{"kta","kato","kata"}', true, true, '인천. 전국 단위 협회 다수.'),
  ('seoul_metro',    '수도권','{"kta","kato","kata"}', true, true, '레거시 호환 코드. 신규 온보딩 저장에는 서울·경기·인천 세부 코드를 사용.')
ON CONFLICT (code) DO UPDATE SET
  display_name_ko = EXCLUDED.display_name_ko,
  governing_associations = EXCLUDED.governing_associations,
  uses_kato = EXCLUDED.uses_kato,
  uses_kata = EXCLUDED.uses_kata,
  notes = EXCLUDED.notes;

UPDATE public.venues
SET region_code = CASE
  WHEN region IN ('서울', '서울시', '서울특별시') THEN 'seoul'
  WHEN region IN ('경기', '경기도') THEN 'gyeonggi'
  WHEN region IN ('인천', '인천시', '인천광역시') THEN 'incheon'
  ELSE region_code
END
WHERE region_code = 'seoul_metro'
  AND region IN ('서울', '서울시', '서울특별시', '경기', '경기도', '인천', '인천시', '인천광역시');

UPDATE public.tournaments
SET region_code = CASE
  WHEN region IN ('서울', '서울시', '서울특별시') THEN 'seoul'
  WHEN region IN ('경기', '경기도') THEN 'gyeonggi'
  WHEN region IN ('인천', '인천시', '인천광역시') THEN 'incheon'
  ELSE region_code
END
WHERE region_code = 'seoul_metro'
  AND region IN ('서울', '서울시', '서울특별시', '경기', '경기도', '인천', '인천시', '인천광역시');
