-- 국화부 · 여자금배부 분리
--
-- 배경: 협회 랭킹표(sub4_5.php)는 국화부와 여자금배부를 별도 랭킹으로 공표하는데,
--   카탈로그는 *_w_winner(여자우승자부) 하나에 두 이름을 synonyms 로 합쳐놨다.
--   org_rankings.division_code FK 를 걸려면 별도 행이 필요하다.
--
-- 방침: *_w_winner 는 삭제하지 않는다. 대회 요강에 "여자우승자부"가 실제로 등장하고,
--   이미 등급으로 등록한 유저가 있을 수 있다(Step 2 확인 결과: 0명, 로컬·프로덕션 동일).
--   synonyms 에서 국화·금배만 떼어 새 코드로 옮긴다.
--
-- 근거: docs/superpowers/specs/2026-08-03-org-ranking-mirror-design.md §8

begin;

-- 1) 기존 winner 에서 국화·금배 alias 제거
--    Step 2 실측으로 *_w_winner 등록 유저가 0건임을 확인했으므로 자격 매칭 회귀는 공집합이다.
update public.tennis_divisions
set synonyms = array_remove(array_remove(synonyms, '국화'), '금배')
where code in ('gj_w_winner', 'jn_w_winner');

-- 2) 국화부 · 여자금배부 신설 (광주·전남 동일 구조)
--    champion_only = true: 광주 규정 제12조가 국화부·금배부를 "우승자 랭킹 포인트" 배점표에
--    넣는다(신인부/개나리부 우승 → 국화부 승격 구조). 기존 *_w_winner 도 true 다.
--    이 값이 틀리면 에러 없이 자격 판정만 조용히 어긋나므로 명시한다.
--    equiv_group: gj/jn 이 같은 suffix 를 공유해야 협회 경계를 넘는 동치 매칭이 선다.
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, event_type,
   equiv_group, age_min, champion_only, is_active, is_ranking_grade)
values
  ('gj_w_gukhwa', 'gj', '국화부', array['국화부', '국화'],
   'advanced', 'female', 'doubles', 'sido_std:w_gukhwa', null, true, true, true),
  ('gj_w_geumbae', 'gj', '여자금배부', array['여자금배부', '금배부', '금배'],
   'advanced', 'female', 'doubles', 'sido_std:w_geumbae', null, true, true, true),
  ('jn_w_gukhwa', 'jn', '국화부', array['국화부', '국화'],
   'advanced', 'female', 'doubles', 'sido_std:w_gukhwa', null, true, true, true),
  ('jn_w_geumbae', 'jn', '여자금배부', array['여자금배부', '금배부', '금배'],
   'advanced', 'female', 'doubles', 'sido_std:w_geumbae', null, true, true, true)
on conflict (code) do update set
  org_code = excluded.org_code,
  label_ko = excluded.label_ko,
  synonyms = excluded.synonyms,
  skill_tier = excluded.skill_tier,
  gender = excluded.gender,
  event_type = excluded.event_type,
  equiv_group = excluded.equiv_group,
  age_min = excluded.age_min,
  champion_only = excluded.champion_only,
  is_active = excluded.is_active,
  is_ranking_grade = excluded.is_ranking_grade;

commit;
