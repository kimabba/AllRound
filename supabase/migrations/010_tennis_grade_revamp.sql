-- 010_tennis_grade_revamp.sql
-- 테니스 등급을 부수 기반에서 경력 연수 기반으로 변경
--   under1y : 1년 미만
--   y1to3   : 1년 이상 3년 미만
--   y3to5   : 3년 이상 5년 미만
--   over5y  : 5년 이상

-- user_sports 체크 제약 교체
alter table public.user_sports
  drop constraint user_sports_grade_check;

alter table public.user_sports
  add constraint user_sports_grade_check check (
    (sport = 'tennis'  and grade in ('under1y', 'y1to3', 'y3to5', 'over5y'))
    or
    (sport = 'futsal'  and grade in ('beginner', 'intermediate', 'advanced'))
  );

-- 기존 테니스 등급 데이터 마이그레이션 (로컬 시드 데이터 보호)
update public.user_sports
set grade = case grade
  when 'rookie' then 'under1y'
  when 'div5'   then 'under1y'
  when 'div4'   then 'y1to3'
  when 'div3'   then 'y3to5'
  when 'div2'   then 'over5y'
  when 'div1'   then 'over5y'
  else grade
end
where sport = 'tennis'
  and grade in ('rookie', 'div5', 'div4', 'div3', 'div2', 'div1');

-- tournaments.eligible_grades 배열 내 구 등급 교체
update public.tournaments
set eligible_grades = (
  select array_agg(
    case g
      when 'rookie' then 'under1y'
      when 'div5'   then 'under1y'
      when 'div4'   then 'y1to3'
      when 'div3'   then 'y3to5'
      when 'div2'   then 'over5y'
      when 'div1'   then 'over5y'
      else g
    end
  )
  from unnest(eligible_grades) as g
)
where sport = 'tennis'
  and eligible_grades && array['rookie','div5','div4','div3','div2','div1'];
