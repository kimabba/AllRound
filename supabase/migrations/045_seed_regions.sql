-- 045: Seed regions table with all supported region codes.
-- Matches REGION_CODES / REGION_LABELS in _shared/enums.ts.

INSERT INTO public.regions (code, display_name_ko, governing_associations, uses_kato, uses_kata, notes) VALUES
  ('gwangju',        '광주',           '{"gj"}',                true, true, '1차 타겟 지역. 광주테니스협회(GJTA) 관할.'),
  ('jeonnam',        '전남',           '{"jn"}',                true, true, '1차 타겟 지역. 전남테니스협회(JNTA) 관할.'),
  ('seoul',          '서울',           '{"kta","kato","kata"}', true, true, '서울. 전국 단위 협회 다수.'),
  ('gyeonggi',       '경기',           '{"kta","kato","kata"}', true, true, '경기도. 전국 단위 협회 다수.'),
  ('incheon',        '인천',           '{"kta","kato","kata"}', true, true, '인천. 전국 단위 협회 다수.'),
  ('seoul_metro',    '수도권',          '{"kta","kato","kata"}', true, true, '레거시 호환 코드. 신규 온보딩 저장에는 서울·경기·인천 세부 코드를 사용.'),
  ('busan_ulsan_gn', '부산·울산·경남',   '{"kta"}',               false, false, NULL),
  ('daegu_gb',       '대구·경북',       '{"kta"}',               false, false, NULL),
  ('chungcheong',    '충청',           '{"kta"}',               false, false, '대전·세종·충남·충북'),
  ('gangwon',        '강원',           '{"kta"}',               false, false, NULL),
  ('jeju',           '제주',           '{"kta"}',               false, false, NULL)
ON CONFLICT (code) DO UPDATE SET
  display_name_ko = EXCLUDED.display_name_ko,
  governing_associations = EXCLUDED.governing_associations,
  uses_kato = EXCLUDED.uses_kato,
  uses_kata = EXCLUDED.uses_kata,
  notes = EXCLUDED.notes;
