-- 랭킹 등급 ↔ 대회 출전 종목 분리 (1단계: 카탈로그 분류)
--
-- 문제:
--   tennis_divisions 한 테이블이 두 역할을 겸하고 있다.
--     (a) 유저가 "내 등급"으로 속하는 것      → 온보딩 부서 칩
--     (b) 대회가 "이 종목을 연다"고 여는 것    → tournaments.eligible_grades
--   대회에만 존재하는 종목(초급자부·마스터즈부·혼합복식)이 (a)에도 섞여 들어와,
--   유저가 자기 랭킹 등급으로 고를 수 없는 것을 고를 수 있었다.
--   실제로 gj_m_masters 를 등급으로 등록한 유저가 1명 있다.
--
-- 해결:
--   행을 나누지 않고 축을 하나 추가한다. is_ranking_grade = false 면 (b) 전용이다.
--   대회 쪽(eligible_grades)은 건드리지 않는다 — 대회는 그 종목을 실제로 연다.
--
-- kimabba 확인 (2026-07-29):
--   · 초급자부  — "구별 대회로 등록된다"
--   · 마스터즈부 — "광주 전남에서 대회가 있어 랭킹은 아니야"
--   · 개나리/국화 여자 매핑 — "여자는 맞음" (유지)
--   · "금배" synonym — 그대로 둔다
--   · 지동부 — 종목 전용으로 추가
--   · 점수 — 정수로만 저장
--   · KTFS·local — 비활성화
--
-- 초급자부 1차 사료 (2026-07-29 실물 확인, coach.gjtennis.kr):
--   「2026 광주오픈 국제 챌린저 초급자 테니스대회」·「제9회 광주광역시 협회장배
--   광주생활체육 테니스대회(초보자)」 요강 부서표에서 '초급자부'는 **묶음 라벨**이고
--   실제 개설 종목은 1년부·3년부다. 참가자격 원문:
--     "테니스에 입문한지 3년 미만 인자"
--     "광주, 전남 공식대회 출전 자 출전불가"
--   경력 기준이며, 랭킹대회 출전 이력이 있으면 오히려 못 나온다 → 등급이 아니다.
--
-- 주의: 기존 event_type 컬럼(doubles/mixed/couple)은 **복식 형태** 구분이다.
--       이번 축과 이름만 비슷하고 뜻이 다르므로 별도 컬럼을 쓴다.

begin;

-- ── 1) 축 추가 ────────────────────────────────────────────────────────────
-- default true: 기존 54행의 대부분이 랭킹 등급이고, 예외만 아래에서 내린다.
-- 앱이 이 컬럼을 모르는 구버전이어도 동작이 바뀌지 않는다(하위호환).
alter table public.tennis_divisions
  add column if not exists is_ranking_grade boolean not null default true,
  add column if not exists score_min smallint,
  add column if not exists score_max smallint;

comment on column public.tennis_divisions.is_ranking_grade is
  '개인이 자기 랭킹 등급으로 속할 수 있는가. false = 대회 출전 종목 전용(온보딩에 노출 금지).';
comment on column public.tennis_divisions.score_min is
  '부서 참가자격 점수 하한(정수). 요강이 0.1~8.0 이면 0. 근거 없는 부서는 null.';
comment on column public.tennis_divisions.score_max is
  '부서 참가자격 점수 상한(정수). 요강이 0.1~8.0 이면 8. 근거 없는 부서는 null.';

-- 둘 다 있으면 min <= max, 값은 0~10 (요강 등급 표기 범위).
alter table public.tennis_divisions
  drop constraint if exists tennis_divisions_score_range_chk;
alter table public.tennis_divisions
  add constraint tennis_divisions_score_range_chk check (
    (score_min is null or score_min between 0 and 10)
    and (score_max is null or score_max between 0 and 10)
    and (score_min is null or score_max is null or score_min <= score_max)
  );

-- ── 2) 종목 전용으로 내린다 ───────────────────────────────────────────────
update public.tennis_divisions
set is_ranking_grade = false
where code in (
  -- 경력 기준 별도 대회. 랭킹대회 출전자는 출전 불가(위 사료 참조).
  'gj_m_beginner', 'jn_m_beginner',
  -- 대회는 열리나 개인 랭킹 등급이 아니다(kimabba 확인).
  'gj_m_masters', 'jn_m_masters',
  -- 남녀/부부가 짝을 이루는 종목. 개인이 속하는 등급이 아니다.
  'kta_mixed', 'kato_mixed', 'kato_couple'
);

-- ── 3) 지동부 추가 (종목 전용) ────────────────────────────────────────────
-- 광주 신청현황표에 실재하나 카탈로그에 없었다. 랭킹은 지도자는 지도자부 등급으로,
-- 동호인은 골드(금배) 등급으로 **각자** 적립되므로 지동부 자체는 등급이 아니다.
-- synonyms 를 ['지동부'] 하나로 좁게 둔다 — '지동'만 두면 요강 본문 아무 데나 걸린다
-- (gj_cross 가 ['크로스'] 하나로 오탐원이 됐던 것과 같은 실수를 피한다).
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, event_type, is_active, is_ranking_grade)
values
  ('gj_m_jidong', 'gj', '지동부', array['지동부'], null, 'male', 'doubles', true, false)
on conflict (code) do nothing;

-- ── 4) 종목 전용 코드를 유저 등록에서 걷어낸다 ────────────────────────────
-- 대회(eligible_grades)에서는 빼지 않는다. 대회는 실제로 그 종목을 연다.
-- 적용 시점 실측: gj_m_masters 1건(division_codes = [gj_m_instructor, gj_m_masters])
-- → 지도자부가 남아 빈 배열이 되지 않는다.
update public.user_tennis_orgs u
set division_codes = (
  select coalesce(array_agg(c order by c), '{}')
  from unnest(u.division_codes) as c
  where c not in (
    select d.code from public.tennis_divisions d where d.is_ranking_grade = false
  )
)
where exists (
  select 1 from unnest(u.division_codes) as c
  join public.tennis_divisions d on d.code = c
  where d.is_ranking_grade = false
);

-- ── 5) 실체 없는 협회의 부서 비활성화 ─────────────────────────────────────
-- KTFS: 2016년 KTA 에 흡수·소멸한 협회. local: 클럽 자체 임시 등급.
-- 둘 다 대회 0건·유저 0명. 행은 남기고 노출만 끊는다(참조가 생겼을 때 라벨 해석 유지).
update public.tennis_divisions
set is_active = false
where org_code in ('ktfs', 'local');

-- ── 6) 부서별 점수 범위 (근거 있는 것만) ──────────────────────────────────
-- 출처: 광주광역시테니스협회 부서별 참가자격요건. 소수부는 버린다(kimabba 결정).
--   오픈부 0.1~8.0 / 골드부 1.0~7.0 / 일반부 1.0~4.0 / 지도자부 0.1~4.0
-- 전남은 "등급의 분류는 광주·전남 협회가 공동 결정"이라는 문구까지만 확인됐고
-- 부서별 점수 범위 원문은 확보하지 못했다 → 추정하지 않고 null 로 둔다.
update public.tennis_divisions set score_min = 0, score_max = 8 where code = 'gj_m_open';
update public.tennis_divisions set score_min = 1, score_max = 7 where code = 'gj_m_gold';
update public.tennis_divisions set score_min = 1, score_max = 4 where code = 'gj_m_general';
update public.tennis_divisions set score_min = 0, score_max = 4 where code = 'gj_m_instructor';

-- ponytail: user_tennis_orgs.division_codes 에 종목 전용 코드가 못 들어가게 하는
-- 트리거는 달지 않았다. 쓰기 경로가 온보딩 하나뿐이고 거기서 필터하기 때문이다.
-- PostgREST 직행으로 넣는 경로가 실제로 생기면 그때 enforce_eligible_grade_format 과
-- 같은 형태의 테이블 트리거를 단다.

commit;
