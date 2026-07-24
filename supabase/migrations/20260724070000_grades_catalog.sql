-- JY-146 P3-a: 종목별 등급 사전 테이블(grades)
--
-- 그동안 등급 정의는 user_sports_grade_check(CHECK 제약)에만 있었고, 표시용 라벨은
-- 어디에도 없어 Dart/TS 두 벌로 복제됐다. 테니스 부서(tennis_divisions)와 달리 등급은
-- DB 가 코드 목록만 알고 라벨은 몰랐던 셈이다.
--
-- 이 마이그레이션은 등급을 tennis_divisions 와 같은 사전 테이블 패턴으로 승격한다.
--   - 등급 추가·개명이 INSERT/UPDATE 로 끝난다(CHECK 교체 마이그레이션 불필요).
--   - 라벨이 DB 에 생기므로 클라 상수는 캐시가 되고, harness 게이트가 seed 와의
--     일치를 강제한다.
--   - user_sports 는 복합 FK 로 grades 를 참조해 CHECK 를 대체한다.
--
-- 운영 데이터 확인(2026-07-24): user_sports 의 (sport, grade) 조합은 전부 아래 9개
-- 안에 있다. FK 부착 시 위반 0.

create table if not exists public.grades (
  sport public.sport not null,
  code text not null,
  label_ko text not null,
  -- 표시 순서. UI 선택지·필터 칩이 이 순서를 따른다(입문 → 선출).
  sort_order int not null,
  -- 폐기 등급은 삭제하지 않고 false 로 둔다. 기존 user_sports 행이 FK 로 남아 있고,
  -- 과거 데이터의 라벨 표시도 계속 필요하기 때문이다.
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (sport, code)
);

-- PK 는 (sport, code) 지만 code 자체도 전역 유일해야 한다. 클라이언트는 라벨을
-- code 단일 키 맵으로 들고 있어(gradeLabels), 종목 간 code 가 겹치면 한쪽 라벨이
-- 다른 종목까지 덮어쓴다. 등급 관리가 관리자 INSERT 로 이뤄지는 이상 이 규칙은
-- 하네스(seed 검사)만으로는 부족하고 DB 가 지켜야 한다.
--
-- ponytail: 이건 데이터 불변식이 아니라 현재 Flutter 구현(Map<String,String>)의 천장이다.
-- 3번째 종목이 'beginner' 같은 자연스러운 code 를 재사용해야 하면 관리자 INSERT 가
-- 23505 로 막힌다. 그때는 gradeLabel(code) 를 (sport, code) 복합 키로 바꾸고
-- 이 제약을 drop 하는 게 정공법이다(JY-146 P4, 종목 확장 시).
alter table public.grades
  drop constraint if exists grades_code_unique;
alter table public.grades
  add constraint grades_code_unique unique (code);

comment on table public.grades is
  '종목별 등급 사전(JY-146). user_sports.grade 의 정본이며 라벨까지 보유한다.';
comment on constraint grades_code_unique on public.grades is
  'code 는 종목을 가로질러 유일해야 한다 — 클라 라벨 맵이 code 단일 키다.';
comment on column public.grades.is_active is
  '폐기 등급은 false. 행을 지우면 과거 user_sports 행의 FK 가 깨지므로 삭제하지 않는다.';

create index if not exists grades_active_idx
  on public.grades (sport, sort_order) where is_active;

-- "테이블 권한은 넓게 + RLS 가 행 단위 통제" 모델. 신규 테이블은 같은 마이그레이션에서
-- grant 를 명시한다(docs/rules/DATABASE_RULES.md · 가드 011_api_role_grants.test.sql).
-- 빠뜨리면 클린 재생 시 앱에서 등급 선택지가 통째로 안 보인다.
grant all on table public.grades to anon, authenticated, service_role;

alter table public.grades enable row level security;

-- 읽기는 로그인 사용자 전체(선택지 표시), 쓰기는 관리자만 — tennis_divisions 와 동일.
drop policy if exists grades_read on public.grades;
create policy grades_read on public.grades
  for select using (auth.role() = 'authenticated');

drop policy if exists grades_admin on public.grades;
create policy grades_admin on public.grades
  for all using (public.is_admin()) with check (public.is_admin());

insert into public.grades (sport, code, label_ko, sort_order) values
  ('tennis', 'under1y', '1년 미만', 1),
  ('tennis', 'y1to3', '1~3년', 2),
  ('tennis', 'y3to5', '3~5년', 3),
  ('tennis', 'over5y', '5년 이상', 4),
  ('futsal', 'intro', '입문', 1),
  ('futsal', 'beginner', '초급', 2),
  ('futsal', 'intermediate', '중급', 3),
  ('futsal', 'advanced', '고급', 4),
  ('futsal', 'elite', '선출', 5)
on conflict (sport, code) do update
  set label_ko = excluded.label_ko,
      sort_order = excluded.sort_order;

-- CHECK → FK 교체.
--
-- 부착과 검증을 분리한다. 검증형 ADD FOREIGN KEY 는 user_sports 전체를 스캔하는 동안
-- 쓰기와 충돌하는 락을 잡으므로, 장기 트랜잭션 뒤에서 배포가 무기한 대기하거나
-- 락 획득 후 프로필 저장이 큐잉·타임아웃된다. NOT VALID 부착은 스캔이 없어 락 구간이
-- 짧고, VALIDATE 는 ShareUpdateExclusiveLock 이라 쓰기를 막지 않는다.
-- SET LOCAL 이 아니라 SET 이다 — 마이그레이션은 트랜잭션 블록으로 실행되지 않아
-- SET LOCAL 이 조용히 무시된다(25P01 경고만 남는다). 아래에서 default 로 되돌린다.
set lock_timeout = '3s';

alter table public.user_sports
  drop constraint if exists user_sports_grade_check;

alter table public.user_sports
  drop constraint if exists user_sports_grade_fkey;

alter table public.user_sports
  add constraint user_sports_grade_fkey
  foreign key (sport, grade) references public.grades (sport, code)
  not valid;

set lock_timeout = default;

-- 위반 행이 있으면 여기서 예외가 난다(조용히 통과시키면 정본이 두 개가 된다).
-- 운영 데이터 확인(2026-07-24) 기준 위반 0 이지만, 배포 시점에 신규 데이터가
-- 생겼을 수 있으므로 검증을 생략하지 않는다.
alter table public.user_sports
  validate constraint user_sports_grade_fkey;

-- FK 는 (sport, code) 의 "존재"만 본다. 관리자가 등급을 폐기(is_active=false)해도
-- 사용자가 PostgREST 로 직접 그 등급을 배정할 수 있어, 클라이언트 선택지 필터가
-- 유일한 방어가 된다. 신규 배정만 막고 기존 행은 그대로 두어야 하므로(폐기해도
-- 과거 데이터는 남는다) FK 로는 표현할 수 없고 트리거로 강제한다.
create or replace function public.enforce_active_grade()
returns trigger
language plpgsql
set search_path = ''
as $func$
begin
  if exists (
    select 1 from public.grades g
    where g.sport = new.sport and g.code = new.grade and g.is_active
  ) then
    return new;
  end if;
  -- 폐기 등급이라도 **그 사용자가 이미 갖고 있던 값**이면 재저장을 허용한다.
  -- 프로필 저장은 upsert(ON CONFLICT DO UPDATE)인데 Postgres 는 충돌 해소 전에
  -- BEFORE INSERT 를 먼저 발동시킨다. INSERT 경로에서 기존 행을 보지 않으면
  -- 폐기 등급 보유자가 프로필을 저장할 수 없다("신규 배정만 제한" 의도와 어긋난다).
  if exists (
    select 1 from public.user_sports us
    where us.user_id = new.user_id
      and us.sport = new.sport
      and us.grade = new.grade
  ) then
    return new;
  end if;
  raise exception '비활성 등급은 배정할 수 없습니다: % / %', new.sport, new.grade
    using errcode = '23514';
end;
$func$;

comment on function public.enforce_active_grade() is
  'user_sports 신규 배정을 활성 등급으로 제한한다(JY-146). 기존 행은 건드리지 않는다.';

-- 신규 함수 권한은 같은 마이그레이션에서 명시한다(docs/rules/DATABASE_RULES.md).
-- PUBLIC 기본 EXECUTE 에 기대면 그게 회수되는 순간 트리거가 조용히 죽는다.
grant execute on function public.enforce_active_grade() to anon, authenticated, service_role;

drop trigger if exists user_sports_active_grade on public.user_sports;
drop trigger if exists user_sports_active_grade_insert on public.user_sports;
drop trigger if exists user_sports_active_grade_update on public.user_sports;

create trigger user_sports_active_grade_insert
  before insert on public.user_sports
  for each row execute function public.enforce_active_grade();

-- UPDATE 는 값이 **실제로 바뀔 때만** 검사한다. `UPDATE OF grade` 는 값이 그대로여도
-- SET 목록에 컬럼이 있기만 하면 발동하는데, 그러면 폐기 등급을 쓰던 사용자가 프로필을
-- 재저장할 때 막힌다 — "신규 배정만 제한하고 기존 행은 보존" 이라는 의도와 어긋난다.
-- (WHEN 절에서는 tg_op 를 쓸 수 없어 INSERT 와 트리거를 나눈다.)
create trigger user_sports_active_grade_update
  before update of sport, grade on public.user_sports
  for each row
  when (new.grade is distinct from old.grade or new.sport is distinct from old.sport)
  execute function public.enforce_active_grade();
