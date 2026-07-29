-- 광주 구별 협회 대회를 받기 위한 부서 보강 + 크롤 소스 등록.
--
-- 배경:
--   광주는 시협회(gjtennis.kr) 말고도 산하 조직이 각자 대회를 연다. 크롤 소스에는
--   시협회·전남·KATO 셋뿐이라 그 대회들이 통째로 빠지고 있었다.
--     coach.gjtennis.kr      광주광역시 테니스지도자협회 (초급자 대회)
--     gwangsangu.gjtennis.kr 광산구테니스협회
--     bukgu.gjtennis.kr      광주광역시 북구테니스협회
--     seogu.gjtennis.kr      광주광역시 서구테니스협회
--
--   네 사이트 모두 시협회와 **같은 양식의 신청현황표**를 쓴다(실물 확인, 2026-07-29):
--     참가 부서 | 구분 | 신청기간 | 경기일시 | 현재신청팀
--   그래서 부서·마감·경기일이 표에서 정확히 나온다. 기존 파서가 이 표를 이미 찾는다.
--
--   실물에서 미매칭으로 남은 부서명이 곧 이 조직들의 실제 부서였다:
--     테린이(남) · 테린이(여)              지도자회 초급자 대회
--     남자부(개인)_어르신60+/65+/70+/75+   서구 어르신 대회
--     단체전(일반부) · 단체전_클럽대항전(남)
--     골드부 · 여자신인부                   (북구 — 시협회 체계를 그대로 쓴다)
--
-- kimabba 결정 (2026-07-30):
--   · 테린이 = 초급자부. 표에 남/여가 따로 있으므로 **여자 초급자부를 신설**해 가른다.
--   · 어르신60+/65+/70+ = 기존 KSTF 시니어에 동의어로 묶는다.
--     75+ 는 KSTF 에 없고 공식 근거도 못 찾아 **미매칭으로 둔다**(없는 부서를 만들지 않는다).
--   · 단체전은 **경기 형식이지 부서가 아니다**. 표의 '구분' 칸에 단식/복식/단체전이
--     따로 있다. 사전에 넣지 않으므로 '단체전(일반부)' 은 괄호 안 '일반부' 로만 걸린다.

begin;

-- ── 1) 여자 초급자부 신설 ─────────────────────────────────────────────────
-- 초급자부는 남자용 하나뿐이었다(gj_m_beginner, gender=male). 지도자회 표에는
-- 테린이(남)·테린이(여)가 둘 다 있어, 여자 대회가 남자 부서로 라벨링되는 걸 막는다.
-- 초급자부와 같은 이유로 **대회 종목 전용**이다(경력 기준, 공식대회 출전자 불가).
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, event_type,
   equiv_group, age_min, champion_only, is_active, is_ranking_grade)
values
  ('gj_w_beginner', 'gj', '여자초급자부', array['여자초급자부', '테린이(여)'],
   null, 'female', 'doubles', null, null, false, true, false)
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

-- ── 2) 남자 초급자부에 '테린이(남)' 추가 ──────────────────────────────────
-- '테린이' 만 넣으면 안 된다 — substring 매칭이라 '테린이(여)' 셀에도 걸려
-- 여자 대회가 남자 부서로 잡힌다. 성별 표기까지 포함해 좁힌다.
update public.tennis_divisions
set synonyms = (
  select array_agg(distinct s order by s)
  from unnest(synonyms || array['테린이(남)']) as s
)
where code = 'gj_m_beginner';

-- ── 3) 어르신 연령부를 KSTF 시니어에 묶는다 ───────────────────────────────
-- 표 값이 '남자부(개인)_어르신60+' 라 substring 으로 걸린다.
-- '어르신60+' 와 '어르신65+' 는 서로의 부분문자열이 아니므로 교차 오탐이 없다.
update public.tennis_divisions
set synonyms = (
  select array_agg(distinct s order by s)
  from unnest(synonyms || array['어르신60+']) as s
)
where code = 'kstf_60';

update public.tennis_divisions
set synonyms = (
  select array_agg(distinct s order by s)
  from unnest(synonyms || array['어르신65+']) as s
)
where code = 'kstf_65';

update public.tennis_divisions
set synonyms = (
  select array_agg(distinct s order by s)
  from unnest(synonyms || array['어르신70+']) as s
)
where code = 'kstf_70';

-- ── 4) 크롤 소스 4행 ──────────────────────────────────────────────────────
-- org_code 는 넷 다 'gj' 다. 구 협회를 tennis_orgs 에 새로 넣지 않는 이유:
--   유저가 온보딩에서 고르는 것은 **소속 협회**이고, 구 대회에도 광주 등급으로 나간다.
--   협회를 늘리면 온보딩 선택지만 늘고 등급 체계는 그대로다.
-- 시각은 시협회(21:00)·전남(21:15)과 겹치지 않게 흩는다.
insert into public.crawl_sources
  (slug, name, url, sport, region, region_code, org_code, source_type,
   parser_module, schedule_cron, enabled, notes)
values
  ('tennis-gwangju-coach', '광주 테니스지도자협회 대회신청',
   'http://coach.gjtennis.kr/bbs/board.php?bo_table=game',
   'tennis', '광주', 'gwangju', 'gj', 'board',
   'gnuboard-sub5-5-contest', '30 21 * * *', true,
   '초급자(테린이) 대회 전담. 시협회 주최 대회도 여기서 접수한다.'),
  ('tennis-gwangju-gwangsangu', '광산구테니스협회 대회신청',
   'http://gwangsangu.gjtennis.kr/bbs/board.php?bo_table=game',
   'tennis', '광주', 'gwangju', 'gj', 'board',
   'gnuboard-sub5-5-contest', '35 21 * * *', true, null),
  ('tennis-gwangju-bukgu', '광주 북구테니스협회 대회신청',
   'http://bukgu.gjtennis.kr/bbs/board.php?bo_table=game',
   'tennis', '광주', 'gwangju', 'gj', 'board',
   'gnuboard-sub5-5-contest', '40 21 * * *', true, null),
  ('tennis-gwangju-seogu', '광주 서구테니스협회 대회신청',
   'http://seogu.gjtennis.kr/bbs/board.php?bo_table=game',
   'tennis', '광주', 'gwangju', 'gj', 'board',
   'gnuboard-sub5-5-contest', '45 21 * * *', true, null)
on conflict (slug) do update set
  name = excluded.name,
  url = excluded.url,
  org_code = excluded.org_code,
  region_code = excluded.region_code,
  parser_module = excluded.parser_module,
  schedule_cron = excluded.schedule_cron,
  enabled = excluded.enabled,
  notes = excluded.notes;

commit;
