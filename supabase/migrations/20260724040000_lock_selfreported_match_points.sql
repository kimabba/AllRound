-- match_entries 자기신고 경로 잠금
--
-- 배경: 061 의 match_entries_self 는 RLS 가 본인 전체 CRUD(FOR ALL)를 허용한다.
--   앱 쓰기 다수가 PostgREST 직행이라, 인증 토큰만 있으면 앱 UI 없이도
--   points_earned = 99999 를 직접 INSERT/UPDATE 할 수 있다.
--
-- 결정(2026-07-24): 랭킹 점수의 원천은 서버가 검증한 결과만 쓴다.
--   자기신고 match_entries 는 "내 대회 이력"으로만 남기고 점수는 항상 0 으로 고정한다.
--   설계 근거: docs/design/ranking-points-design-review.html
--
-- FOR ALL + WITH CHECK 의 함정(codex 리뷰 GATE FAIL): WITH CHECK 는 INSERT/UPDATE 후행에만
--   걸리고 DELETE 엔 전혀 안 걸린다. 그래서 단일 FOR ALL 정책으로는, 유저가 자기 소유의
--   admin/crawl 검증 행(source!='manual' 또는 points>0)을 DELETE 로 지우거나(패배·저평가
--   기록 세탁) UPDATE 로 무력화할 수 있었다 — 이 마이그레이션이 막으려던 것과 같은 범주의 위협.
--   → self 경로를 command 별로 분리한다. 검증된 행은 self 로 "읽기"만 가능하고
--     수정/삭제는 admin(match_entries_admin) · service_role(RLS 우회) 전용이 된다.
--
-- 지금 거는 이유: match_entries/match_rounds 가 0 건이라 백필·정합성 검사가 필요 없다.

begin;

drop policy if exists match_entries_self on public.match_entries;
drop policy if exists match_entries_self_read on public.match_entries;
drop policy if exists match_entries_self_insert on public.match_entries;
drop policy if exists match_entries_self_modify on public.match_entries;
drop policy if exists match_entries_self_delete on public.match_entries;

-- 읽기: 본인 행 전체. 검증된 결과(내 대회 성적)도 본인은 봐야 한다.
create policy match_entries_self_read on public.match_entries
  for select
  using (user_id = (select auth.uid()));

-- 삽입: 자기신고는 points_earned = 0, source = 'manual' 만 허용.
create policy match_entries_self_insert on public.match_entries
  for insert
  with check (
    user_id = (select auth.uid())
    and points_earned = 0
    and source = 'manual'
  );

-- 수정: 자기신고(manual·0점) 행만, 수정 후에도 manual·0 이어야 한다.
--   USING 이 검증된 행을 걸러내므로(source!='manual' or points>0) self 로는 손댈 수 없다.
create policy match_entries_self_modify on public.match_entries
  for update
  using (
    user_id = (select auth.uid())
    and points_earned = 0
    and source = 'manual'
  )
  with check (
    user_id = (select auth.uid())
    and points_earned = 0
    and source = 'manual'
  );

-- 삭제: 자기신고 행만. 검증된 행은 self 로 삭제 불가(기록 세탁 차단).
create policy match_entries_self_delete on public.match_entries
  for delete
  using (
    user_id = (select auth.uid())
    and points_earned = 0
    and source = 'manual'
  );

-- 같은 대회·부서 중복 등록 차단. 앱 코드가 아니라 DB 가 막는다.
create unique index if not exists match_entries_user_tournament_division_key
  on public.match_entries (user_id, tournament_id, division);

commit;
