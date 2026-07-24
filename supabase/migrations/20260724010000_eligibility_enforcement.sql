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

-- ── DELETE 게이트: "남의 콘텐츠를 지우는 권한"에만 건다 ───────────────
-- 이 세 테이블은 매니저가 타인의 글·이벤트·모집글을 삭제할 수 있어 권한 행위다.
-- 반대로 이탈성 삭제(이벤트 참석 취소, 일정 공유 해제, 즐겨찾기 해제 등)에는
-- 이 정책을 붙이지 않는다 — 막으면 사용자를 가두게 된다(해당 테이블들엔 기존
-- DELETE 정책이 그대로 살아 있고, 여기서 자격 조건을 덧대지 않을 뿐이다).
--
-- 작성자 본인 삭제는 자기 정리라 항상 허용한다. 자격을 잃은(또는 아직 갖추지
-- 못한) 사용자가 자기 글을 못 지우고 갇히는 상황을 만들지 않기 위해서다.
do $$
declare
  t text;
  author_col text;
begin
  foreach t in array array[
    'club_posts',
    'club_events',
    'club_recruiting_posts'
  ]
  loop
    author_col := case t when 'club_posts' then 'author_id' else 'created_by' end;
    execute format('drop policy if exists %I on public.%I', t || '_requires_eligible_del', t);
    execute format(
      'create policy %I on public.%I as restrictive for delete to authenticated
         using ((select public.is_eligible_member()) or %I = (select auth.uid()))',
      t || '_requires_eligible_del', t, author_col
    );
  end loop;
end;
$$;

-- ── schedule_shares: 수신자의 "거절"은 이탈이므로 자격 없이도 가능해야 한다 ─
-- 위 generic UPDATE 게이트가 거절까지 막으므로, 이 테이블은 대상에서 제외하고
-- (아래 drop) 공유 "생성"만 자격을 요구한다. 거절·수락 응답은 기존 정책대로.
drop policy if exists schedule_shares_requires_eligible_upd on public.schedule_shares;

-- ── respond_club_event: SECURITY DEFINER 라 RLS 를 우회한다 ──────────
-- club_event_attendees 에 붙인 restrictive 정책이 이 경로엔 적용되지 않으므로
-- 함수 안에서 직접 막는다. 참석('going')은 참여 행위라 자격이 필요하고,
-- 불참('not_going')은 이탈이므로 자격 없이도 허용한다.
-- 본문은 기존 정의에 자격 검사 한 블록만 덧댄 것이다.
create or replace function public.respond_club_event(p_event_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_capacity integer;
  v_going integer;
  v_current text;
begin
  if p_status not in ('going', 'not_going') then
    raise exception 'invalid attendance status';
  end if;

  if not public.is_event_club_member(p_event_id) then
    raise exception 'club membership required';
  end if;

  -- 참석 기록은 참여 행위 → 자격 필요. 불참(이탈)은 그대로 허용.
  -- (아래는 기존 정의 원문 그대로다. 이 블록 외에는 바꾸지 않는다.)
  if p_status = 'going' and not public.is_eligible_member() then
    raise exception 'phone verification required';
  end if;

  select capacity
  into v_capacity
  from public.club_events
  where id = p_event_id
  for update;

  select status
  into v_current
  from public.club_event_attendees
  where event_id = p_event_id
    and user_id = auth.uid();

  if p_status = 'going'
    and v_current is distinct from 'going'
    and v_capacity is not null
  then
    select count(*)
    into v_going
    from public.club_event_attendees
    where event_id = p_event_id
      and status = 'going';

    if v_going >= v_capacity then
      raise exception 'event capacity reached';
    end if;
  end if;

  insert into public.club_event_attendees (
    event_id,
    user_id,
    status,
    responded_at
  )
  values (p_event_id, auth.uid(), p_status, now())
  on conflict (event_id, user_id) do update
    set status = excluded.status,
        responded_at = excluded.responded_at;
end;
$function$;

revoke execute on function public.respond_club_event(uuid, text) from public, anon;
grant execute on function public.respond_club_event(uuid, text) to authenticated;

-- ── Storage 업로드: 콘텐츠 업로드도 참여 행위 → 자격으로 승격 ────────
-- 기존 정책은 연령만 검증했다. is_eligible_member() 가 연령 검증을 포함하므로
-- 교체해도 연령 게이트는 유지되고 전화 인증만 추가된다.
-- 제외 대상(그대로 연령만 유지):
--   profile-avatars  → 온보딩 단계에서 올린다. 게이트하면 자격 획득 경로가 막힌다.
--   ugc-report-evidence → 신고는 안전 기능이라 자격과 무관하게 열어둔다.
-- 원본 정책의 bucket·소유자 조건과 USING/CHECK 구성은 그대로 두고 술어만 바꾼다.
do $$
declare
  b text;
  p text;
begin
  -- INSERT 전용 버킷
  foreach b in array array['club-posts', 'tournament-posters']
  loop
    p := case b when 'club-posts' then 'club_posts_storage_insert'
                else 'tournament_posters_owner_insert' end;
    execute format('drop policy if exists %I on storage.objects', p);
    execute format(
      'create policy %I on storage.objects for insert to authenticated
         with check (bucket_id = %L
           and owner_id = (select (auth.uid())::text)
           and (select public.is_eligible_member()))',
      p, b
    );
  end loop;

  -- INSERT + UPDATE 버킷
  foreach b in array array['club-logos', 'club-intro-images']
  loop
    p := case b when 'club-logos' then 'club_logos_owner' else 'club_intro_images_owner' end;

    execute format('drop policy if exists %I on storage.objects', p || '_insert');
    execute format(
      'create policy %I on storage.objects for insert to authenticated
         with check (bucket_id = %L
           and owner_id = (select (auth.uid())::text)
           and (select public.is_eligible_member()))',
      p || '_insert', b
    );

    execute format('drop policy if exists %I on storage.objects', p || '_update');
    execute format(
      'create policy %I on storage.objects for update to authenticated
         using (bucket_id = %L and owner_id = (select (auth.uid())::text))
         with check (bucket_id = %L
           and owner_id = (select (auth.uid())::text)
           and (select public.is_eligible_member()))',
      p || '_update', b, b
    );
  end loop;
end;
$$;
