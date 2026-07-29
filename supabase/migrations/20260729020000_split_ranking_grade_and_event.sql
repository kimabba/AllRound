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
--
-- 이 단계가 **끝내지 않는 것** (codex 지적, 의도적으로 남긴다):
--   자격 매칭은 여전히 배열 교집합이다(tournaments_for_user · 챗 검색 RPC). 종목 전용
--   코드로만 열리는 대회는 유저 division_codes 와 겹칠 수 없으니 only_my_grade 필터와
--   홈 추천에서 빠진다. 전체 목록·수동 부서 필터에서는 그대로 보인다.
--   이는 **회귀가 아니라 기존 상태의 고착**이다 — 그 코드를 등급으로 가진 유저가 이미
--   0명이라 지금도 아무에게도 매칭되지 않는다. 다만 앞으로도 그럴 수 없게 된다.
--   실제 자격(KATO 혼합복식·부부혼합, KTA 혼합복식)은 남녀 각자의 부서·연령·입상 이력
--   조합으로 판정되므로, 등급 배열 하나로는 애초에 표현할 수 없다. 개인 자격 → 종목
--   매핑과 3값 판정(가능/불가/알 수 없음)은 다음 단계에서 다룬다.

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
-- equiv_group·age_min·champion_only 를 굳이 적는 이유: 아래 do update 가 **이 목록에
-- 있는 것만** 덮는다. 빠뜨리면 기존 행의 그 값이 살아남아 재실행이 정본으로 수렴하지
-- 않는다(로컬에서 equiv_group='junk' 를 심어 재현 확인).
--   equiv_group  — 광주↔전남 동일 부서를 묶는 키. 지동부는 광주 전용이라 null.
--   age_min      — 연령 하한 없음.  champion_only — 우승자 한정 아님.
insert into public.tennis_divisions
  (code, org_code, label_ko, synonyms, skill_tier, gender, event_type,
   equiv_group, age_min, champion_only, is_active, is_ranking_grade)
values
  ('gj_m_jidong', 'gj', '지동부', array['지동부'], null, 'male', 'doubles',
   null, null, false, true, false)
on conflict (code) do update set
  -- do nothing 이면 이 코드가 다른 값으로 이미 있을 때 교정하지 못한다. 2번 UPDATE 는
  -- 목록에 gj_m_jidong 이 없어 손대지 않고, 4번은 is_ranking_grade=true 인 행을
  -- 걷어내지 않는다 — 재실행이 정본으로 수렴하도록 **이 행이 선언하는 값 전부**를 덮는다.
  -- synonyms 를 빼면 안 된다(codex): 기존 행에 ['지동'] 같은 넓은 동의어가 있으면
  -- 이 블록이 막으려던 바로 그 오탐이 살아남는다.
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

-- ── 4a) 표시용 division 문자열을 먼저 맞춘다 ──────────────────────────────
-- division 은 division_codes 라벨의 사본이고(예: '마스터즈부 · 지도자부'),
-- 챗 컨텍스트(functions/chat/context.ts)는 배열이 아니라 이 문자열을 읽는다. 배열만
-- 고치면 매칭에서 뺀 부서가 AI 문맥에는 계속 실린다(codex).
--
-- **4번보다 먼저** 실행한다 — 배열이 정리된 뒤에는 "무엇이 빠졌는지"를 알 수 없다.
-- division 은 PK 의 일부라(user_id, org, division) 이 UPDATE 는 행 식별자를 바꾼다.
-- 그래서 같은 (user_id, org)에 목표 문자열이 이미 있으면 **건너뛴다** — PK 충돌로
-- 마이그레이션이 죽는 대신 그 행은 손대지 않는다(다음 온보딩 저장 때 맞춰진다).
update public.user_tennis_orgs u
set division = x.new_label
from (
  select
    y.*,
    -- 같은 (user_id, org)의 여러 행이 **한 문장 안에서** 같은 문자열로 수렴하면
    -- 아래 not exists 로는 못 막는다 — 그건 UPDATE 전 스냅샷만 보기 때문이다.
    -- 실제로 재현했다: ['지도자부','마스터즈부'] 와 ['지도자부','초급자부'] 가 둘 다
    -- '지도자부' 가 되면서 duplicate key. 수렴 그룹당 한 행만 바꾼다.
    row_number() over (
      partition by y.user_id, y.org, y.new_label order by y.division
    ) as rn
  from (
    select
      u2.user_id,
      u2.org,
      u2.division,
      (select string_agg(d.label_ko, ' · ' order by array_position(u2.division_codes, d.code))
       from public.tennis_divisions d
       where d.code = any (u2.division_codes) and d.is_ranking_grade) as new_label
    from public.user_tennis_orgs u2
    where exists (
      select 1 from public.tennis_divisions d
      where d.code = any (u2.division_codes) and not d.is_ranking_grade
    )
  ) y
) x
where u.user_id = x.user_id and u.org = x.org and u.division = x.division
  and x.new_label is not null
  and x.new_label <> u.division
  and x.rn = 1
  and not exists (
    select 1 from public.user_tennis_orgs c
    where c.user_id = u.user_id and c.org = u.org and c.division = x.new_label
  );

-- ── 4) 종목 전용 코드를 유저 등록에서 걷어낸다 ────────────────────────────
-- 대회(eligible_grades)에서는 빼지 않는다. 대회는 실제로 그 종목을 연다.
-- 적용 시점 실측: gj_m_masters 1건(division_codes = [gj_m_instructor, gj_m_masters])
-- → 지도자부가 남아 빈 배열이 되지 않는다.
-- 종목 전용**만** 갖고 있던 행이 있으면 배열이 '{}' 가 된다(로컬 재현 확인). 실측에는
-- 그런 행이 없고, 앞으로는 7번 트리거가 그 상태를 만들지 못하게 막는다.
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

-- ── 7) 새 불변식을 DB 에서 강제한다 ───────────────────────────────────────
-- 처음엔 "쓰기 경로가 온보딩 하나뿐"이라 보고 트리거를 생략했다. codex 리뷰 2건이
-- 같은 구멍을 지적했고, 확인해보니 틀린 전제였다:
--   · 앱은 user_tennis_orgs 에 PostgREST 로 직접 upsert 한다(services/user_api.dart)
--   · RLS 는 본인 행인지와 연령만 본다(20260718030000) — 코드 유효성 검사가 없다
--   · 이 마이그레이션보다 앱 배포가 늦으면, 그 사이 구버전 UI 가 종목 전용 칩을
--     계속 보여주고 저장해 4번의 정리를 곧바로 되돌린다
-- 그러면 "등급과 종목의 분리"가 서버 정본이 아니라 최신 UI 버전에만 의존하게 된다.
-- enforce_eligible_grade_format(20260726010000)과 같은 형태로, 모든 경로가 반드시
-- 지나가는 테이블 트리거에 검사를 단다.
--
-- **등록된 코드 중 is_ranking_grade=false 인 것만** 막는다. 미등록 코드는 통과시킨다 —
-- 의미 검증까지 하면 새 부서를 넣는 순서에 따라 저장이 막히고, 그건 이 트리거가
-- 지켜야 할 불변식이 아니다(같은 이유로 tournaments 쪽은 형식만 본다).
create or replace function public.enforce_user_division_is_ranking_grade()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  bad text;
begin
  if new.division_codes is null or array_length(new.division_codes, 1) is null then
    return new;
  end if;

  select string_agg(d.code, ', ' order by d.code)
  into bad
  from public.tennis_divisions d
  where d.code = any (new.division_codes)
    and d.is_ranking_grade = false;

  if bad is not null then
    raise exception
      'division_codes 에 대회 종목 전용 부서가 들어왔다: %. 유저는 랭킹 등급만 가질 수 있다.',
      bad
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_user_division_is_ranking_grade on public.user_tennis_orgs;
create trigger enforce_user_division_is_ranking_grade
  before insert or update of division_codes on public.user_tennis_orgs
  for each row
  execute function public.enforce_user_division_is_ranking_grade();

commit;
