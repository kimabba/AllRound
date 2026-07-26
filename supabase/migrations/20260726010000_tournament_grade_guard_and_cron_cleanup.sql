-- P0 3건 (2026-07-26 · security-engineer·backend-architect 독립 검토 + 운영 실측)
--
-- 1) tournaments.eligible_grades 형식 가드
--    등급 검증은 Edge(tournaments-submit)에만 있었다. 그러나 RLS 정책
--    tournaments_user_submit 이 authenticated 의 PostgREST 직행 draft INSERT 를 허용하고
--    eligible_grades 에는 FK·CHECK 가 하나도 없어서, 로그인 사용자가 Edge 를 건너뛰고
--    임의 문자열을 넣을 수 있었다. 운영에서 재현했다(롤백 완료):
--      insert ... eligible_grades = ['<script>alert(1)</script>', 'DROP TABLE', '아무거나'] → 성공
--    그 draft 는 tournaments_bulk_approve(status='draft' 만 확인)로 published 가 될 수 있다.
--
--    **정책을 회수하지 않는 이유**: Edge 함수 자신이 그 정책으로 INSERT 한다
--    (tournaments-submit/index.ts 의 user client). 회수하면 정문까지 막혀 제보가 죽는다
--    — #320 에서 권한 회수가 RPC 자신을 막았던 것과 같은 구조다. 그래서 경로를 막는 대신
--    **모든 경로(Edge·직행·크롤러·관리자)가 반드시 지나가는 테이블 트리거**에 검사를 단다.
--
--    검사는 **형식만** 한다(^[a-z0-9_]+$ · 길이 상한). 값의 의미 검증(grades 대조)은 여기서
--    하지 않는다 — eligible_grades 에는 등급 코드뿐 아니라 부서 코드(gj_m_gold)도 들어가고,
--    부서 정본은 tennis_divisions 라 grades FK 는 성립하지 않는다. 또 크롤러가 새 부서를
--    만나면 의미 검증은 크롤 자체를 멈춘다. 형식 가드는 실제 피해(임의 문자열·스크립트 문자열
--    주입)를 막으면서 크롤을 세우지 않는다. 적용 전 운영 전수 검사: 위반 0건.
--
-- 2) save_user_sports 의 anon EXECUTE 회수
--    proacl 실측 = {postgres=X, anon=X, authenticated=X, service_role=X}. 함수는 auth.uid()
--    null 을 28000 으로 막아 실해는 없지만(fail-closed), 최소권한 원칙상 anon 은 필요 없다.
--    revoke ... from public 은 anon 의 **명시 grant** 를 걷지 못하므로 대상을 직접 적는다.
--
-- 3) format-pending cron 중복 해제
--    운영 cron.job 에 동일 스케줄(2-59/5)·동일 명령이 둘이다:
--      jobid 11 'format-pending'            ← 20260719065613 이 관리하는 정본
--      jobid 9  'format-pending-every-5min' ← 레포 어디에도 없다(수동 등록 잔재)
--    20260719065613 의 정리 목록이 'format-pending','format-pending-5min' 뿐이라
--    '-every-5min' 이름이 살아남았다. 5분마다 2회 호출 = Edge·Gemini 비용 이중.
--    데이터 오염은 없다(format_pending_claim 이 for update skip locked + claim_token).

begin;

-- ── 1) eligible_grades 형식 가드 ──────────────────────────────────────────
-- 트리거로 하는 이유: CHECK 제약은 배열 원소 순회를 subquery 없이 표현하기 번거롭고,
-- 위반 시 어느 값이 문제인지 알려주지 못한다. 트리거는 문제 값을 메시지에 담는다.
create or replace function public.enforce_eligible_grade_format()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  bad text;
begin
  if new.eligible_grades is null then
    return new;
  end if;

  -- cardinality: array_length(arr, 1) 은 **1차원 길이**만 세므로 ARRAY[['a',…],['b',…]] 로
  -- 상한을 우회할 수 있다. cardinality 는 전체 원소 수를 센다.
  if cardinality(new.eligible_grades) > 50 then
    raise exception 'eligible_grades 원소가 너무 많습니다 (최대 50개)'
      using errcode = '23514';
  end if;

  -- NULL 원소는 별도로 잡는다. `g !~ '...'` 는 g 가 NULL 이면 NULL(=거짓 취급)이라
  -- 형식 검사만으로는 ARRAY['ok', NULL] 이 통과한다.
  if exists (select 1 from unnest(new.eligible_grades) as g where g is null) then
    raise exception 'eligible_grades 에 NULL 원소가 있습니다'
      using errcode = '23514';
  end if;

  select g into bad
  from unnest(new.eligible_grades) as g
  where g !~ '^[a-z0-9_]+$' or length(g) > 64
  limit 1;

  if bad is not null then
    raise exception 'eligible_grades 형식 위반: %', bad
      using errcode = '23514',
            hint = '등급·부서 코드는 소문자·숫자·밑줄만 사용합니다(최대 64자).';
  end if;

  return new;
end;
$$;

comment on function public.enforce_eligible_grade_format() is
  'tournaments.eligible_grades 원소 형식(^[a-z0-9_]+$·64자·50개) 강제. Edge 우회 직행 INSERT 방어(#319 후속).';

drop trigger if exists enforce_eligible_grade_format on public.tournaments;
create trigger enforce_eligible_grade_format
  before insert or update of eligible_grades on public.tournaments
  for each row
  execute function public.enforce_eligible_grade_format();

-- ── 2) anon EXECUTE 회수 ──────────────────────────────────────────────────
revoke execute on function public.save_user_sports(jsonb) from anon;

-- ── 3) cron 중복 해제 ─────────────────────────────────────────────────────
-- 이름으로 지운다(jobid 는 환경마다 다르다). 로컬·CI 재생본에는 이 잔재가 없으므로
-- 존재할 때만 지운다 — 없다고 마이그레이션이 실패하면 안 된다.
do $$
declare
  rec record;
begin
  for rec in
    select jobid from cron.job where jobname = 'format-pending-every-5min'
  loop
    perform cron.unschedule(rec.jobid);
  end loop;
end;
$$;

commit;
