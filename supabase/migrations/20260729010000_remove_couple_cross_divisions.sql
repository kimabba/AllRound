-- 광주·전남의 '부부부'·'크로스대회' 부서 제거.
--
-- 근거:
--   · 부부부 — 광주광역시테니스협회 부서별 참가자격요건 원문에 '부부부' 가 한 번도
--     나오지 않는다. 시드 단계에서 들어간 것으로 보이며 실재 근거를 찾지 못했다.
--     (KATO 의 '부부혼합부' kato_couple 은 규정에서 확인되므로 그대로 둔다.)
--   · 크로스대회 — 요강의 '크로스' 는 부서가 아니라 **대진 추첨 방식**이다.
--       "지도자부 4강 골드부 4강 크로스 추첨"
--       "여자 우승자부 4강(국화2, 금배2), 신인부 4강 크로스 추첨"
--     게다가 synonyms 가 ['크로스'] 하나라 요강 본문의 '크로스 추첨' 어디에나
--     걸려 개설되지도 않은 부서가 대회에 붙는 오탐원이었다.
--
--   kimabba 확인: 둘 다 제거. (2026-07-29)
--
-- 참고: tournaments.eligible_grades / user_tennis_orgs.division_codes 는 text[] 라
-- FK 가 없다. 남은 코드를 직접 걷어낸 뒤 사전 행을 지운다.

-- 1) 대회에 붙은 코드 제거 (배열에서 해당 원소만 빼고 나머지는 보존)
update public.tournaments t
set eligible_grades = (
  select coalesce(array_agg(g order by g), '{}')
  from unnest(t.eligible_grades) as g
  where g <> all (array['gj_couple', 'gj_cross', 'jn_couple', 'jn_cross'])
)
where t.eligible_grades && array['gj_couple', 'gj_cross', 'jn_couple', 'jn_cross'];

-- 2) 유저 등록에 붙은 코드 제거 (현재 0건이나, 재실행 안전성을 위해 함께 처리)
update public.user_tennis_orgs u
set division_codes = (
  select coalesce(array_agg(c order by c), '{}')
  from unnest(u.division_codes) as c
  where c <> all (array['gj_couple', 'gj_cross', 'jn_couple', 'jn_cross'])
)
where u.division_codes && array['gj_couple', 'gj_cross', 'jn_couple', 'jn_cross'];

-- 3) 사전 행 삭제
delete from public.tennis_divisions
where code in ('gj_couple', 'gj_cross', 'jn_couple', 'jn_cross');
