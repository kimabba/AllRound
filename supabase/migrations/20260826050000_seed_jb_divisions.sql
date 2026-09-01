-- P6 전북(jbsta.com) 협회·부서·크롤소스 seed
--
-- 정본은 docs/kb/grades/jb.divisions.json 이며, 이 seed 와 JSON 의 필드 일치는
-- supabase/functions/tests/grade_kb_verify_test.ts 가 CI 에서 강제한다(KATO 방식).
-- 근거: 2026-08 jbsta.com 대회일정 게시물 21건 참가부서 셀 실측 — 전북은
-- 금·은·동배(메달) 승강 체계. equiv_group 은 타 협회 동치 근거가 없어 전부 null.
--
-- 전제: 20260710030000_regions_17sido_crawl_source_cols.sql (regions 'jeonbuk' 존재, FK)

-- 1) tennis_orgs — 전북 협회 등록 (기존 20260710020000 시드에 없음)
-- label_ko/short_label/sort_order 는 표시 정본(JY-135). sort_order 95 = 전남(90)과
-- 시·군/클럽(100) 사이. 이 값은 app/test/fixtures/org_fallback.json 스냅샷·Dart 폴백과
-- check_org_parity.py + Flutter 스냅샷 테스트로 일치가 강제된다.
insert into public.tennis_orgs
  (code, name_ko, label_ko, short_label, org_type, region_code, division_scheme, is_active, sort_order) values
  ('jb', '전북특별자치도테니스협회', '전북특별자치도테니스협회 (JBSTA)', '전북협회', 'sido', 'jeonbuk', 'jb_medal', true, 95)
on conflict (code) do update set
  name_ko = excluded.name_ko,
  label_ko = excluded.label_ko,
  short_label = excluded.short_label,
  org_type = excluded.org_type,
  region_code = excluded.region_code,
  division_scheme = excluded.division_scheme,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;

-- 2) tennis_divisions — 전북 부서 사전 (파서의 mapDivisionsByDict 가 사용)
-- is_ranking_grade: 개인이 자기 등급으로 속할 수 있는 부서만 true (온보딩 칩 노출).
-- 금동배(금+동 통합 이벤트)·혼합복식·단체전·합산대회는 출전 종목 전용 → false.
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, age_min, champion_only, event_type, equiv_group, is_ranking_grade) values
  ('jb_m_dong',     'jb', '남자동배부',   '{남자동배부}',        'rookie',   'male',   null, false, 'doubles', null, true),
  ('jb_m_geumeun',  'jb', '남자금은배부', '{남자금은배부}',      'advanced', 'male',   null, false, 'doubles', null, true),
  ('jb_m_geumdong', 'jb', '남자금동배부', '{남자금동배부}',      null,       'male',   null, false, 'doubles', null, false),
  ('jb_w_dong',     'jb', '여자동배부',   '{여자동배부}',        'rookie',   'female', null, false, 'doubles', null, true),
  ('jb_w_geumeun',  'jb', '여자금은배부', '{여자금은배부}',      'advanced', 'female', null, false, 'doubles', null, true),
  ('jb_gukhwa',     'jb', '국화부',       '{국화부}',            'advanced', 'female', null, false, 'doubles', null, true),
  ('jb_mixed',      'jb', '혼합복식부',   '{혼합복식부,혼합복식}', null,      'mixed',  null, false, 'mixed',   null, false),
  ('jb_team',       'jb', '단체전',       '{단체전}',            null,       'all',    null, false, 'team',    null, false),
  ('jb_m_hapsan',   'jb', '남자합산대회', '{남자합산}',          null,       'male',   null, false, 'doubles', null, false),
  ('jb_w_hapsan',   'jb', '여자합산대회', '{여자합산}',          null,       'female', null, false, 'doubles', null, false)
on conflict (code) do update set
  org_code = excluded.org_code,
  label_ko = excluded.label_ko,
  synonyms = excluded.synonyms,
  skill_tier = excluded.skill_tier,
  gender = excluded.gender,
  age_min = excluded.age_min,
  champion_only = excluded.champion_only,
  event_type = excluded.event_type,
  equiv_group = excluded.equiv_group,
  is_ranking_grade = excluded.is_ranking_grade;

-- 3) crawl_sources — 전북 대회일정 게시판 (parser_module = registry 키)
-- enabled=false 초기값 — KATO 선례. 배포·라이브 검증(force 크롤로 draft 수집 확인) 후
-- 수동 활성화. url 은 리스트 뷰(&gubun=list) — 기본 뷰는 캘린더라 글 링크가 없다(실측).
insert into public.crawl_sources
  (name, slug, url, sport, region, source_type, parser_module, org_code, region_code, enabled, notes) values
  (
    '전북테니스협회 대회일정',
    'tennis-jeonbuk',
    'https://www.jbsta.com/bbs/board.php?bo_table=schedule&gubun=list',
    'tennis',
    '전북',
    'board',
    'gnuboard5-schedule-board',
    'jb',
    'jeonbuk',
    false,
    'P6 신규 협회. 라이브 검증 후 enabled=true.'
  )
on conflict (slug) do update set
  url = excluded.url,
  parser_module = excluded.parser_module,
  org_code = excluded.org_code,
  region_code = excluded.region_code;
