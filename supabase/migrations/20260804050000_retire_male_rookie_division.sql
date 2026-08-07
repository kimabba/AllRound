-- 남자신인부 폐지 — 남자일반부로 통합됨 (2026-08-04 Commander 확인)
--
-- 협회가 남자신인부를 일반부로 통합해 순위표 공표를 중단했다. 실측:
--   https://gjtennis.kr/sub4_5.php?member_kind=남자신인부
--   → HTTP 200 이지만 표 머리글만 있고 데이터 행 0개 (골드부는 589행)
--   크롤이 8/3 08:48 부터 6회 연속 "파싱 0행" 으로 partial 실패를 찍고 있었다.
--
-- **지우지 않고 비활성화한다.** 이 코드를 참조하는 데이터가 남아 있다:
--   · tournaments.eligible_grades 에 포함한 대회 12건 (실측)
--   · 과거 대회 상세가 이 코드를 라벨로 해석해야 한다
--
-- is_active=false 의 의미(grade_labels.dart 주석과 동일):
--   목록(선택지)에서는 빠지고, **라벨 해석은 계속 된다.**
--   tournaments_for_user 는 is_active 로 거르지 않으므로 기존 12건 매칭도 그대로다(확인함).
--
-- 유저 쪽 사용은 0건이라 온보딩·등급 표시에 영향이 없다(실측:
--   user_sports.grade / user_tennis_orgs.division / division_codes 모두 0).
--
-- 여자신인부(*_w_rookie)는 **살아 있다.** 코드가 비슷해 혼동하기 쉬우니 주의.

begin;

update public.tennis_divisions
   set is_active = false
 where code in ('gj_m_rookie', 'jn_m_rookie');

commit;
