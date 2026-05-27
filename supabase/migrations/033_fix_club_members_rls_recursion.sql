-- 033_fix_club_members_rls_recursion.sql
-- club_members / club_join_requests RLS 무한 재귀(42P17) 수정
--
-- 031_club_management 의 club_members_select 정책이 정책 본문에서 club_members 를
-- 다시 SELECT(EXISTS ...)해 무한 재귀가 발생했다. club_join_requests 의 select/update
-- 정책도 club_members 를 참조해 재귀가 전파된다.
--
-- is_admin() 과 동일하게 SECURITY DEFINER 헬퍼로 멤버십을 평가하면 함수 내부 쿼리가
-- RLS 를 우회하므로 재귀가 끊긴다.

-- 본인이 해당 클럽의 active 멤버인가
create or replace function public.is_active_club_member(p_club_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

-- 본인이 해당 클럽의 owner/manager(active)인가
create or replace function public.is_club_manager(p_club_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and role in ('owner', 'manager')
      and status = 'active'
  );
$$;

-- club_members: 자기참조 EXISTS → 헬퍼로 교체
drop policy if exists club_members_select on public.club_members;
create policy club_members_select on public.club_members
  for select using (
    user_id = auth.uid()
    or public.is_admin()
    or public.is_active_club_member(club_id)
  );

-- club_join_requests: club_members 참조 EXISTS → 헬퍼로 교체
drop policy if exists club_join_requests_select on public.club_join_requests;
create policy club_join_requests_select on public.club_join_requests
  for select using (
    user_id = auth.uid()
    or public.is_admin()
    or public.is_club_manager(club_id)
  );

drop policy if exists club_join_requests_update on public.club_join_requests;
create policy club_join_requests_update on public.club_join_requests
  for update using (
    public.is_admin()
    or public.is_club_manager(club_id)
  );
