-- 20260714130000_users_min_age_gate.sql
-- 만 19세 미만(미성년) 가입 차단 — 연령 게이트 (JY-133).
--
-- 온보딩에서 birth_date 저장 시 서버측에서 만 19세(민법 성년) 미만을 거부한다.
-- 개인정보보호법 §22의2(만 14세 미만 나이 확인) 대응 + 미성년 법정대리인 동의
-- 이슈 회피를 위해 미성년 전체를 차단(kimabba 결정).
--
-- eligibility 는 서버가 source of truth — 클라이언트 게이트만으론 우회 가능하므로
-- DB 트리거로 강제한다. birth_date 컬럼이 바뀔 때(INSERT / UPDATE OF birth_date)만 검사.

create or replace function public.enforce_min_signup_age()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- birth_date 가 (오늘 - 19년) 보다 최근이면 아직 만 19세 미만.
  if new.birth_date is not null
     and new.birth_date > (current_date - interval '19 years') then
    raise exception 'MINOR_NOT_ALLOWED'
      using
        message = '만 19세 이상만 가입할 수 있습니다.',
        errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_min_signup_age on public.users;
create trigger trg_enforce_min_signup_age
  before insert or update of birth_date on public.users
  for each row
  execute function public.enforce_min_signup_age();
