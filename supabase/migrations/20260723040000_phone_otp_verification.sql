-- 20260723040000_phone_otp_verification.sql
-- 가입 신원 무결성용 전화번호 SMS OTP 인증 (신원확인 전용, 로그인 미변경).
--
-- 인증은 "인증된 사용자"(온보딩 단계)가 수행 → verify→가입 사이 claim 토큰 불필요.
-- 원문 번호 미저장: Edge Function 이 pepper 로 HMAC 후 phone_hash/code_hash 만 전달.
-- 재사용 정책 A: 동시 보유 차단(unique) / 탈퇴 후 재가입 허용 / 해시 이력만 보존.
--
-- 신뢰 경계: OTP RPC 는 service_role 전용. Edge Function 만 serviceClient 로 호출하며
-- 사용자 신원(user_id)·rate 파라미터를 서버에서 해결해 넘긴다. authenticated 가
-- PostgREST 로 RPC 를 직접 부르거나 phone_verified_at 을 직접 PATCH 하는 우회를 막는다.

-- ── users: 인증 상태 컬럼 ──────────────────────────────────────────
alter table public.users
  add column if not exists phone_hash text,
  add column if not exists phone_verified_at timestamptz,
  add column if not exists pepper_version smallint not null default 1;

-- 활성 계정 유니크. 탈퇴=완전삭제라 row 소멸 시 자연 해제(재사용 허용).
-- phone_hash NULL 다수 공존은 기본 NULLS DISTINCT.
create unique index if not exists users_phone_hash_key on public.users (phone_hash);

-- 사용자가 자기 row 를 직접 수정해 인증을 위조하지 못하게 가드 확장.
-- 기존 role 가드와 동일 메커니즘: auth.uid() 가 있는(=사용자 JWT) 경로만 차단하고,
-- service_role(auth.uid() null)로 도는 verify RPC 는 통과시킨다.
create or replace function public.prevent_role_self_update()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if old.role is distinct from new.role then
      raise exception 'role 컬럼은 관리자만 변경할 수 있습니다';
    end if;
    if old.phone_verified_at is distinct from new.phone_verified_at
       or old.phone_hash is distinct from new.phone_hash
       or old.pepper_version is distinct from new.pepper_version then
      raise exception '전화번호 인증 정보는 직접 변경할 수 없습니다';
    end if;
  end if;
  return new;
end;
$$;

-- ── phone_otp: 발급·검증·rate limit 통합 (번호당 1행 upsert) ─────────
create table if not exists public.phone_otp (
  phone_hash        text primary key,
  code_hash         text not null,
  expires_at        timestamptz not null,
  attempts          int not null default 0,          -- 검증 실패 카운트
  send_count        int not null default 1,          -- 시간당 발송(fixed window)
  window_started_at timestamptz not null default now(),
  locked_until      timestamptz,                     -- 검증 실패 초과 잠금
  created_at        timestamptz not null default now()
);
alter table public.phone_otp enable row level security;
-- 정책 0개 → SECURITY DEFINER RPC 를 통해서만 접근. 클라이언트 직접 접근 deny.

-- ── phone_otp_daily: 글로벌 일일 발송 상한 (금전 서킷브레이커) ────────
create table if not exists public.phone_otp_daily (
  day        date primary key,
  sent_count int not null default 0
);
alter table public.phone_otp_daily enable row level security;

-- ── phone_otp_user_daily: 계정별 일일 발송 상한 (번호 로테이션 남용 차단) ─
create table if not exists public.phone_otp_user_daily (
  user_id    uuid not null,
  day        date not null,
  sent_count int not null default 0,
  primary key (user_id, day)
);
alter table public.phone_otp_user_daily enable row level security;

-- ── phone_verification_log: 어뷰징 추적 이력 ───────────────────────
create table if not exists public.phone_verification_log (
  id         bigint generated always as identity primary key,
  phone_hash text not null,
  event      text not null check (event in ('verified', 'withdraw')),
  user_id    uuid,   -- FK 없음: 탈퇴 완전삭제와 공존. 추적의 실제 키는 phone_hash.
  created_at timestamptz not null default now()
);
create index if not exists phone_verification_log_hash_idx
  on public.phone_verification_log (phone_hash);
alter table public.phone_verification_log enable row level security;

-- ── withdraw 이력: BEFORE DELETE 트리거 (cascade 삭제도 row 트리거 발화) ─
create or replace function public.log_phone_withdraw()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.phone_hash is not null then
    insert into public.phone_verification_log (phone_hash, event, user_id)
    values (old.phone_hash, 'withdraw', old.id);
  end if;
  return old;
end;
$$;
-- 트리거 함수는 Postgres 가 호출 → Data API 직접 실행 차단.
revoke execute on function public.log_phone_withdraw() from public, anon, authenticated;

drop trigger if exists trg_log_phone_withdraw on public.users;
create trigger trg_log_phone_withdraw
  before delete on public.users
  for each row execute function public.log_phone_withdraw();

-- ── request_phone_otp: rate-limit 게이트 + OTP 저장 (service_role 전용, fail-closed) ─
-- 반환 jsonb: { allowed, reason, retry_after? }. Edge Function 이 RPC 에러 시 발송 금지.
drop function if exists public.request_phone_otp(text, text, int, int, int, int);
create or replace function public.request_phone_otp(
  p_user_id uuid,
  p_phone_hash text,
  p_code_hash text,
  p_ttl_seconds int,
  p_cooldown_seconds int,
  p_hourly_cap int,
  p_daily_global_cap int,
  p_user_daily_cap int
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now       timestamptz := now();
  v_row       public.phone_otp%rowtype;
  v_global    int;
  v_user_sent int;
begin
  -- 같은 번호 동시 첫 요청 레이스 직렬화(M1): 트랜잭션 종료까지 유효.
  perform pg_advisory_xact_lock(hashtext(p_phone_hash)::bigint);

  -- 1) 번호 단위 게이트
  select * into v_row from public.phone_otp where phone_hash = p_phone_hash for update;
  if found then
    if v_row.locked_until is not null and v_row.locked_until > v_now then
      return jsonb_build_object('allowed', false, 'reason', 'LOCKED',
        'retry_after', ceil(extract(epoch from (v_row.locked_until - v_now)))::int);
    end if;
    if v_row.created_at + make_interval(secs => p_cooldown_seconds) > v_now then
      return jsonb_build_object('allowed', false, 'reason', 'COOLDOWN',
        'retry_after',
        ceil(extract(epoch from
          (v_row.created_at + make_interval(secs => p_cooldown_seconds) - v_now)))::int);
    end if;
    if v_row.window_started_at + interval '1 hour' > v_now
       and v_row.send_count >= p_hourly_cap then
      return jsonb_build_object('allowed', false, 'reason', 'HOURLY_LIMIT',
        'retry_after',
        ceil(extract(epoch from
          (v_row.window_started_at + interval '1 hour' - v_now)))::int);
    end if;
  end if;

  -- 2) 계정별 일일 상한(H3) — 한 계정이 번호를 돌려 예산을 소진하지 못하게.
  insert into public.phone_otp_user_daily (user_id, day, sent_count)
    values (p_user_id, current_date, 0)
    on conflict (user_id, day) do nothing;
  select sent_count into v_user_sent from public.phone_otp_user_daily
    where user_id = p_user_id and day = current_date for update;
  if v_user_sent >= p_user_daily_cap then
    return jsonb_build_object('allowed', false, 'reason', 'USER_LIMIT', 'retry_after', 3600);
  end if;

  -- 3) 글로벌 일일 상한(서킷브레이커) — 실제 발송 직전에만 증가.
  insert into public.phone_otp_daily (day, sent_count)
    values (current_date, 0)
    on conflict (day) do nothing;
  select sent_count into v_global from public.phone_otp_daily
    where day = current_date for update;
  if v_global >= p_daily_global_cap then
    return jsonb_build_object('allowed', false, 'reason', 'GLOBAL_LIMIT', 'retry_after', 3600);
  end if;

  update public.phone_otp_daily set sent_count = sent_count + 1 where day = current_date;
  update public.phone_otp_user_daily set sent_count = sent_count + 1
    where user_id = p_user_id and day = current_date;

  -- 4) OTP upsert. 재발송이면 시간당 윈도우 유지·증가, 만료됐으면 리셋.
  insert into public.phone_otp as o
      (phone_hash, code_hash, expires_at, attempts, send_count, window_started_at,
       locked_until, created_at)
    values (p_phone_hash, p_code_hash, v_now + make_interval(secs => p_ttl_seconds),
       0, 1, v_now, null, v_now)
    on conflict (phone_hash) do update set
      code_hash    = excluded.code_hash,
      expires_at   = excluded.expires_at,
      attempts     = 0,
      locked_until = null,
      created_at   = v_now,
      window_started_at = case
        when o.window_started_at + interval '1 hour' <= v_now then v_now
        else o.window_started_at end,
      send_count = case
        when o.window_started_at + interval '1 hour' <= v_now then 1
        else o.send_count + 1 end;

  return jsonb_build_object('allowed', true, 'reason', 'OK');
end;
$$;
revoke execute on function
  public.request_phone_otp(uuid, text, text, int, int, int, int, int)
  from public, anon, authenticated;
grant execute on function
  public.request_phone_otp(uuid, text, text, int, int, int, int, int) to service_role;

-- ── verify_phone_otp: 원자적 시도검증 + 성공 시 users 기록 (service_role 전용) ─
-- 신원은 Edge Function 이 검증한 JWT 에서 뽑아 p_user_id 로 넘긴다(auth.uid 미의존).
drop function if exists public.verify_phone_otp(text, text, int, int);
create or replace function public.verify_phone_otp(
  p_user_id uuid,
  p_phone_hash text,
  p_code_hash text,
  p_max_attempts int,
  p_lock_seconds int
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code_hash text;
  v_attempts  int;
begin
  if p_user_id is null then
    return jsonb_build_object('status', 'UNAUTHENTICATED');
  end if;

  -- 원자적: 시도 카운트 증가를 비교보다 먼저. 만료/잠금/초과면 행 미반환.
  update public.phone_otp
    set attempts = attempts + 1
    where phone_hash = p_phone_hash
      and expires_at > now()
      and (locked_until is null or locked_until <= now())
      and attempts < p_max_attempts
    returning code_hash, attempts into v_code_hash, v_attempts;

  if not found then
    update public.phone_otp
      set locked_until = now() + make_interval(secs => p_lock_seconds)
      where phone_hash = p_phone_hash and expires_at > now();
    return jsonb_build_object('status', 'EXPIRED_OR_LOCKED');
  end if;

  if v_code_hash <> p_code_hash then
    if v_attempts >= p_max_attempts then
      update public.phone_otp
        set locked_until = now() + make_interval(secs => p_lock_seconds)
        where phone_hash = p_phone_hash;
      return jsonb_build_object('status', 'LOCKED');
    end if;
    return jsonb_build_object('status', 'INVALID', 'remaining', p_max_attempts - v_attempts);
  end if;

  -- 성공: users 기록 → 이력. unique 충돌 = 다른 계정이 이미 보유.
  -- (OTP 소비는 성공 확정 후. 카운터 보유 행이지만 verify 성공 = 퍼널 이탈이라 무해.)
  begin
    update public.users
      set phone_hash = p_phone_hash, phone_verified_at = now()
      where id = p_user_id;
  exception when unique_violation then
    return jsonb_build_object('status', 'ALREADY_USED');
  end;

  -- 챌린지만 소멸시키고 rate-limit 카운터 행은 남긴다.
  -- 행을 지우면 "가입→인증→탈퇴→재가입" 회전으로 번호별 한도가 리셋된다.
  -- 빈 code_hash 는 어떤 HMAC 과도 일치하지 않고, 만료 처리로 재시도도 막힌다.
  -- (오래된 행은 cleanup cron 이 정리)
  update public.phone_otp
    set code_hash = '', expires_at = now()
    where phone_hash = p_phone_hash;

  insert into public.phone_verification_log (phone_hash, event, user_id)
    values (p_phone_hash, 'verified', p_user_id);

  return jsonb_build_object('status', 'OK');
end;
$$;
revoke execute on function public.verify_phone_otp(uuid, text, text, int, int)
  from public, anon, authenticated;
grant execute on function public.verify_phone_otp(uuid, text, text, int, int) to service_role;

-- ── RLS 의도 명시 ──────────────────────────────────────────────────
-- 아래 4개 테이블은 "정책 0개 = 전면 거부"가 의도된 설계다. 인증 챌린지와
-- rate-limit 카운터는 사용자·anon 이 읽거나 쓸 이유가 전혀 없고, 접근은 오직
-- SECURITY DEFINER RPC(request/verify_phone_otp)와 service_role 을 통해서만 이뤄진다.
-- 허용 정책을 추가하면 OTP 챌린지·발송 한도가 클라이언트에 노출된다.
comment on table public.phone_otp is
  'OTP 챌린지 + 번호별 rate limit. RLS 정책 없음(전면 거부) — RPC/service_role 전용.';
comment on table public.phone_otp_daily is
  '글로벌 일일 발송 상한 카운터. RLS 정책 없음(전면 거부) — RPC/service_role 전용.';
comment on table public.phone_otp_user_daily is
  '계정별 일일 발송 상한 카운터. RLS 정책 없음(전면 거부) — RPC/service_role 전용.';
comment on table public.phone_verification_log is
  '전화번호 해시 인증·탈퇴 이력(어뷰징 추적). RLS 정책 없음(전면 거부) — service_role 전용.';

-- ── cleanup: 기존 pg_cron 재사용 (하루 1회 만료 OTP·오래된 일일카운터 정리) ─
select cron.schedule('phone-otp-cleanup', '17 4 * * *', $$
  delete from public.phone_otp where expires_at < now() - interval '1 day';
  delete from public.phone_otp_daily where day < current_date - 7;
  delete from public.phone_otp_user_daily where day < current_date - 7;
$$);
