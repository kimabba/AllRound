-- JY-136: 기존 user_tennis_orgs 의 division 라벨 → division_codes 백필.
--
-- 온보딩이 division_codes 를 저장하지 않던 시기(모델에 필드 부재)에 가입한 사용자는
-- division(표시 라벨, "마스터즈부 · 지도자부" 형태)만 있고 division_codes=[] 라
-- 테니스 자격매칭 RPC(expand_division_codes(division_codes) && eligible_grades)의
-- 교집합이 항상 0 → "내 등급 대회" 테니스 추천 0건.
--
-- 라벨은 카탈로그 label 을 ' · ' 로 join 한 문자열이므로(onboarding_screen.dart),
-- 같은 구분자로 분리해 tennis_divisions.label_ko 로 역매칭하여 코드 배열을 채운다.
-- codes 가 이미 채워진 행은 건드리지 않는다(idempotent, 재실행 안전).

update public.user_tennis_orgs u
set division_codes = sub.codes
from (
  select u2.user_id,
         u2.org,
         u2.division,
         array_agg(distinct d.code order by d.code) as codes
  from public.user_tennis_orgs u2
  cross join lateral
    unnest(string_to_array(u2.division, ' · ')) as lbl(label)
  join public.tennis_divisions d
    on d.org_code = u2.org
   and d.label_ko = btrim(lbl.label)
  where coalesce(array_length(u2.division_codes, 1), 0) = 0
    and u2.division is not null
    and u2.division <> 'default'
  group by u2.user_id, u2.org, u2.division
) sub
where u.user_id = sub.user_id
  and u.org = sub.org
  and u.division = sub.division
  and coalesce(array_length(u.division_codes, 1), 0) = 0;
