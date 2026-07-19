-- 032_drop_legacy_clubs_active_policy.sql
-- 레거시 active 기반 clubs SELECT 정책 제거 (보안 수정)
--
-- 031_club_management 에서 clubs 접근제어를 status 기반(clubs_select:
--   status='approved' OR created_by=auth.uid() OR is_admin())으로 전환했으나,
-- 004_clubs 의 clubs_authenticated_read (auth.role()='authenticated' AND active)
-- 정책이 남아 있었다. RLS 의 다중 SELECT 정책은 OR 로 결합되므로, clubs-create 가
-- active 를 명시하지 않아 기본값 active=true 인 status='pending' 클럽이 레거시 정책을
-- 통과해 모든 인증 사용자에게 노출되었다 (어드민 승인 전 비공개가 무력화).
--
-- 레거시 정책을 제거하여 clubs_select 만 유효하게 한다.
drop policy if exists clubs_authenticated_read on public.clubs;

-- 031은 정책 전환을 설명하지만 실제 CREATE POLICY 문이 누락되어 있었다.
-- fresh reset에서도 승인된 클럽과 본인 생성 클럽을 읽을 수 있도록 명시적으로 생성한다.
-- 클럽 생성/수정은 UGC 제재를 검사하는 Edge Function(service role)만 사용한다.
drop policy if exists clubs_select on public.clubs;
create policy clubs_select on public.clubs
  for select to authenticated
  using (
    status = 'approved'
    or created_by = (select auth.uid())
    or public.is_admin()
  );
