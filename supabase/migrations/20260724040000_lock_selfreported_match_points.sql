-- match_entries 자기신고 경로 잠금
--
-- 배경: 061에서 만든 match_entries 는 RLS 가 본인 전체 CRUD 를 허용한다.
--   앱 쓰기 다수가 PostgREST 직행이라, 인증 토큰만 있으면 앱 UI 없이도
--   points_earned = 99999 를 직접 INSERT/UPDATE 할 수 있다.
--   지금은 어느 화면·정렬에도 쓰이지 않아 무해하지만, 랭킹에 연결되는 순간 치명적이다.
--
-- 결정(2026-07-24): 랭킹 점수의 원천은 서버가 검증한 결과만 쓴다.
--   자기신고 match_entries 는 "내 대회 이력"으로만 남기고 점수는 항상 0 으로 고정한다.
--   설계 근거: docs/design/ranking-points-design-review.html
--
-- 지금 거는 이유: match_entries/match_rounds 가 0 건이라 백필·정합성 검사가 필요 없다.
--   데이터가 쌓인 뒤에는 같은 제약이 훨씬 비싸진다.

begin;

-- 1) 자기신고는 points_earned = 0, source = 'manual' 만 허용.
--    admin(match_entries_admin) 과 service_role(RLS 우회) 은 영향 없음 —
--    검증된 점수를 넣는 경로는 그쪽만 남는다.
drop policy if exists match_entries_self on public.match_entries;

create policy match_entries_self on public.match_entries
  for all
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and points_earned = 0
    and source = 'manual'
  );

-- 2) 같은 대회·부서 중복 등록 차단. 앱 코드가 아니라 DB 가 막는다.
create unique index if not exists match_entries_user_tournament_division_key
  on public.match_entries (user_id, tournament_id, division);

commit;
