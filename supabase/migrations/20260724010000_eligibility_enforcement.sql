-- 20260724010000_eligibility_enforcement.sql
-- 계정 자격(standing) 단일 술어 + 참여 쓰기 RLS 강제.
--
-- 배경: 앱은 Edge Function 뿐 아니라 PostgREST 로 직접 쓰는 경로가 20+ 테이블에 있다.
-- 따라서 강제는 "모든 쓰기가 반드시 통과하는 가장 낮은 층"인 RLS 에 둔다.
-- 클라 라우팅 = UX, Edge 가드 = 빠른 실패/에러메시지, RLS = 진짜 경계(3중).
--
-- 순환 의존 주의: 자격을 "얻는 경로"는 절대 게이트하지 않는다.
--   비게이트: users(자기 프로필)·user_sports·user_tennis_orgs(온보딩),
--             OTP 발송/검증, 공개 데이터 읽기, 신고·차단(안전 기능),
--             알림·기기토큰(본인 상태), 즐겨찾기(무해), 가입취소·탈퇴.

-- ── 단일 술어 ──────────────────────────────────────────────────────
-- 규칙은 user_id 파라미터 버전에만 두고, 무인자 버전은 auth.uid() 로 위임한다.
-- 서버가 "제3자"의 자격을 판정해야 하는 경우(예: 클럽 가입 승인 시 신청자)가
-- 있어 파라미터 버전이 필요하며, 규칙이 두 벌로 갈라지는 것을 막는다.

-- 연령 규칙 정본을 파라미터화. 기존 무인자 버전은 여기에 위임한다.
create or replace function public.has_verified_signup_age_id(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users
    where id = p_user_id
      and birth_date is not null
      and birth_date <= (current_date - interval '14 years')::date
  );
$$;
-- 타인 연령 조회가 가능하므로 서버 전용.
revoke execute on function public.has_verified_signup_age_id(uuid) from public, anon, authenticated;
grant execute on function public.has_verified_signup_age_id(uuid) to service_role;

create or replace function public.has_verified_signup_age()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_verified_signup_age_id((select auth.uid()));
$$;

-- 관리자는 별개 신뢰축이므로 면제(모더레이션이 자격 게이트에 묶이지 않게).
create or replace function public.is_eligible_member_id(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.users where id = p_user_id and role = 'admin')
    or (
      public.has_verified_signup_age_id(p_user_id)
      and exists (
        select 1 from public.users
        where id = p_user_id and phone_verified_at is not null
      )
    );
$$;
revoke execute on function public.is_eligible_member_id(uuid) from public, anon, authenticated;
grant execute on function public.is_eligible_member_id(uuid) to service_role;

create or replace function public.is_eligible_member()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_eligible_member_id((select auth.uid()));
$$;

comment on function public.is_eligible_member is
  '계정 자격 단일 술어: 관리자 또는 (만14세 연령검증 + 전화번호 인증). 참여 쓰기 RLS·Edge 가드가 참조한다.';

revoke execute on function public.is_eligible_member() from public, anon;
grant execute on function public.is_eligible_member() to authenticated, service_role;

-- ── 참여(사회적 쓰기) 테이블에 restrictive 정책 부착 ────────────────
-- restrictive 는 기존 permissive 정책과 AND 로 결합되므로 기존 소유권·멤버십
-- 로직을 건드리지 않고 자격 조건만 덧댄다(개별 revert 도 쉬움).
-- service_role 은 RLS 자체를 우회하므로 Edge 의 서버 작업엔 영향 없다.
do $$
declare
  t text;
begin
  foreach t in array array[
    'clubs',
    'club_posts',
    'club_post_comments',
    'club_post_mentions',
    'club_events',
    'club_event_attendees',
    'club_recruiting_posts',
    -- 신청자는 직접 UPDATE 권한이 없고(정책상 admin·매니저만) 취소는 Edge 경유라,
    -- 게이트를 걸어도 이탈 경로가 막히지 않는다. 미인증 매니저의 직접 조작만 차단된다.
    'club_join_requests',
    'chat_messages',
    'schedule_shares',
    'match_entries',
    'match_rounds',
    'tournaments',
    'venues'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', t || '_requires_eligible_ins', t);
    execute format(
      'create policy %I on public.%I as restrictive for insert to authenticated
         with check ((select public.is_eligible_member()))',
      t || '_requires_eligible_ins', t
    );

    execute format('drop policy if exists %I on public.%I', t || '_requires_eligible_upd', t);
    execute format(
      'create policy %I on public.%I as restrictive for update to authenticated
         using ((select public.is_eligible_member()))
         with check ((select public.is_eligible_member()))',
      t || '_requires_eligible_upd', t
    );
  end loop;
end;
$$;
