-- 20260714130000_users_min_age_gate.sql
-- 만 14세 미만 가입 차단 — 연령 게이트 (JY-133).
--
-- 온보딩에서 birth_date 저장 시 서버측에서 만 14세 미만을 거부한다.
-- 개인정보보호법 §22의2: 만 14세 미만 아동의 개인정보는 법정대리인 동의가 필요하므로,
-- 나이 확인 없이 14세 미만을 받지 않도록 가입 자체를 차단한다(법정대리인 동의 플로우 회피).
-- 만 14세 이상은 본인 동의로 가입 가능 — 제한하지 않는다.
--
-- eligibility 는 서버가 source of truth — 클라이언트 게이트만으론 우회 가능하므로
-- DB 트리거로 강제한다. birth_date 컬럼이 바뀔 때(INSERT / UPDATE OF birth_date)만 검사.

create or replace function public.enforce_min_signup_age()
returns trigger
language plpgsql
set search_path = ''
as $func$
begin
  -- birth_date 가 (오늘 - 14년) 보다 최근이면 아직 만 14세 미만.
  if new.birth_date is not null
     and new.birth_date > (current_date - interval '14 years') then
    -- format string 과 using message 를 함께 쓰면 'MESSAGE already specified' 오류.
    -- 코드(MINOR_NOT_ALLOWED)는 message 앞에 붙여 클라이언트가 파싱하게 한다.
    raise exception using
      errcode = 'check_violation',
      message = 'MINOR_NOT_ALLOWED: 만 14세 이상만 가입할 수 있습니다.';
  end if;
  return new;
end;
$func$;

drop trigger if exists trg_enforce_min_signup_age on public.users;
create trigger trg_enforce_min_signup_age
  before insert or update of birth_date on public.users
  for each row
  execute function public.enforce_min_signup_age();
