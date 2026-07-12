-- P5 KATO 부서 seed
--
-- tennis_divisions 에 KATO(한국테니스발전협의회) 부서 10개를 등록한다.
-- 정본은 docs/kb/grades/kato.divisions.json 이며, 이 seed 와 JSON 의 필드 일치는
-- supabase/functions/tests/grade_kb_verify_test.ts 가 CI 에서 강제한다(블로커 #3 드리프트 차단).
--
-- 설계: docs/superpowers/specs/2026-07-11-p5-kato-grade-kb-and-parser-design.md ②
-- 전제: 20260710020000_tennis_orgs_divisions_catalog.sql (tennis_orgs 에 'kato' 존재, FK)
--
-- 원칙(전문가 3인 검토):
--   - synonyms 철자변형 필수(마스터스/마스터즈, 챌린저/챌린져) — 안 넣으면 라이브 매칭 실패
--   - bare '혼합'/'퓨처스' 금지(부서 간 충돌) — 이미 disambiguated
--   - equiv_group 전부 null — expand_division_codes 가 age/champion/gender 미검이라
--     이름만 같고 자격 다른 협회 간 공유는 오탐. 협회 경계 공유는 별도 패스.

insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, age_min, champion_only, event_type, equiv_group) values
  ('kato_gaenari',   'kato', '개나리부',    '{개나리부,개나리}',                'rookie',       'female', null, false, 'doubles', null),
  ('kato_gukhwa',    'kato', '국화부',      '{국화부,국화}',                    'intermediate', 'mixed',  40,   false, 'doubles', null),
  ('kato_challenger','kato', '챌린저부',    '{챌린저부,챌린저,챌린져부,챌린져}', 'advanced',     'all',    null, true,  'doubles', null),
  ('kato_masters',   'kato', '마스터스부',  '{마스터스부,마스터스,마스터즈부,마스터즈}', 'open',  'all',    55,   true,  'doubles', null),
  ('kato_veteran',   'kato', '베테랑부',    '{베테랑부,베테랑}',                'intermediate', 'all',    55,   false, 'doubles', null),
  ('kato_instructor','kato', '지도자부',    '{지도자부,지도자}',                'advanced',     'all',    40,   false, 'doubles', null),
  ('kato_mixed',     'kato', '혼합복식부',  '{혼합복식부,혼합복식}',            null,           'mixed',  null, false, 'mixed',   null),
  ('kato_couple',    'kato', '부부혼합부',  '{부부혼합부,부부혼합}',            null,           'mixed',  null, false, 'couple',  null),
  ('kato_futures_m', 'kato', '남자퓨처스부','{남자퓨처스부,남자퓨처스}',        'rookie',       'male',   null, false, 'doubles', null),
  ('kato_futures_w', 'kato', '여자퓨처스부','{여자퓨처스부,여자퓨처스}',        'rookie',       'female', null, false, 'doubles', null)
on conflict (code) do update set
  org_code = excluded.org_code,
  label_ko = excluded.label_ko,
  synonyms = excluded.synonyms,
  skill_tier = excluded.skill_tier,
  gender = excluded.gender,
  age_min = excluded.age_min,
  champion_only = excluded.champion_only,
  event_type = excluded.event_type,
  equiv_group = excluded.equiv_group;

-- KATO 크롤 소스 등록 (parser_module = registry 키 'kato-openlist').
-- enabled=false 초기값 — 배포·라이브 검증(force 크롤로 draft 수집 확인) 후 수동 활성화.
-- org_code='kato'(부서사전 로드 키), region_code=null(전국), sport='tennis'.
insert into public.crawl_sources
  (name, slug, url, sport, region, source_type, parser_module, org_code, region_code, enabled, notes) values
  (
    'KATO 대회일정',
    'tennis-kato',
    'https://kato.kr/openList',
    'tennis',
    null,
    'board',
    'kato-openlist',
    'kato',
    null,
    false,
    'P5 신규 협회. 라이브 검증 후 enabled=true.'
  )
on conflict (slug) do update set
  url = excluded.url,
  parser_module = excluded.parser_module,
  org_code = excluded.org_code;
